#!/usr/bin/env bash
# claude-usage-poll.sh — Query Claude Code /usage via dedicated tmux sessions
#
# Supports multiple accounts (configured in config.yaml).
# Each account gets its own tmux session. All accounts poll in parallel.
#
# Single account (no accounts in config): backward-compatible, uses default OAuth.
# Multi-account: reads accounts from config.yaml, uses CLAUDE_CODE_OAUTH_TOKEN.

set -uo pipefail
unset TMUX

TMUX_BIN={{tmux}}
CLAUDE={{claude}}
CONFIG_FILE="{{config_file}}"
USAGE_DIR="{{home}}/.local/share/claude-usage"

# ── Account discovery ───────────────────────────────────
# Returns lines of "name<TAB>token" pairs.
# If no accounts configured, returns empty (triggers legacy single-account mode).
discover_accounts() {
  python3 -c "
import re
try:
    text = open('$CONFIG_FILE').read()
    # Find the accounts: block (everything indented after 'accounts:')
    m = re.search(r'^accounts:\s*\n((?:[ \t]+.*\n)*)', text, re.MULTILINE)
    if not m: exit()
    block = m.group(1)
    # Split into entries by '- name:' and extract name + token
    for entry in re.split(r'(?=\s*-\s+name:)', block):
        nm = re.search(r'name:\s*(\S+)', entry)
        tk = re.search(r'token:\s*(\S+)', entry)
        if nm and tk:
            print(nm.group(1) + '\t' + tk.group(1))
except: pass
" 2>/dev/null
}

# ── Per-account poll function ───────────────────────────
poll_account() {
  local ACCT_NAME="$1"
  local ACCT_TOKEN="$2"

  # Derive file paths based on account name
  if [ -z "$ACCT_NAME" ]; then
    # Legacy single-account mode
    local SESSION="claude_usage_mon"
    local USAGE_FILE="/tmp/claude-usage.json"
    local USAGE_LOG="$USAGE_DIR/usage.jsonl"
  else
    local SESSION="claude_usage_mon_${ACCT_NAME}"
    local USAGE_FILE="/tmp/claude-usage-${ACCT_NAME}.json"
    local USAGE_LOG="$USAGE_DIR/usage-${ACCT_NAME}.jsonl"
  fi

  local PHASES=()

  # Write current phase to the usage file (stale-while-revalidate pattern)
  write_phase() {
    PHASES+=("$1")
    local pj=""
    for p in "${PHASES[@]}"; do
      [ -n "$pj" ] && pj+=","
      pj+="\"$p\""
    done
    local prev_pct="" prev_reset="" prev_weekly="" prev_weekly_reset=""
    if [ -f "$USAGE_FILE" ]; then
      { read -r prev_pct; read -r prev_reset; read -r prev_weekly; read -r prev_weekly_reset; } < <(python3 -c "
import json
try:
    d=json.load(open('$USAGE_FILE'))
    print(d.get('pct','')); print(d.get('reset_ts','')); print(d.get('weekly_pct','')); print(d.get('weekly_reset_ts',''))
except: print(); print(); print(); print()
" 2>/dev/null) || true
    fi
    local extra=""
    [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
    [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
    [ -n "$prev_weekly" ] && extra+="\"weekly_pct\":$prev_weekly,"
    [ -n "$prev_weekly_reset" ] && extra+="\"weekly_reset_ts\":$prev_weekly_reset,"
    local acct_json=""
    [ -n "$ACCT_NAME" ] && acct_json="\"account\":\"$ACCT_NAME\","
    printf '{%s%s"phase":"%s","phases":[%s],"ts":%d}\n' "$extra" "$acct_json" "$1" "$pj" "$(date +%s)" > "$USAGE_FILE"
  }

  write_error_with_diag() {
    local error="$1"
    local diag="$2"
    local pj=""
    for p in "${PHASES[@]}"; do
      [ -n "$pj" ] && pj+=","
      pj+="\"$p\""
    done
    local diag_json="[]"
    if [ -n "$diag" ]; then
      diag_json=$(printf '%s' "$diag" | python3 -c 'import sys,json; print(json.dumps([l.rstrip() for l in sys.stdin.read().split("\n") if l.strip()]))')
    fi
    local prev_pct="" prev_reset="" prev_weekly="" prev_weekly_reset=""
    if [ -f "$USAGE_FILE" ]; then
      { read -r prev_pct; read -r prev_reset; read -r prev_weekly; read -r prev_weekly_reset; } < <(python3 -c "
import json
try:
    d=json.load(open('$USAGE_FILE'))
    print(d.get('pct','')); print(d.get('reset_ts','')); print(d.get('weekly_pct','')); print(d.get('weekly_reset_ts',''))
except: print(); print(); print(); print()
" 2>/dev/null) || true
    fi
    local extra=""
    [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
    [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
    [ -n "$prev_weekly" ] && extra+="\"weekly_pct\":$prev_weekly,"
    [ -n "$prev_weekly_reset" ] && extra+="\"weekly_reset_ts\":$prev_weekly_reset,"
    local acct_json=""
    [ -n "$ACCT_NAME" ] && acct_json="\"account\":\"$ACCT_NAME\","
    printf '{%s%s"error":"%s","phases":[%s],"diag":%s,"ts":%d}\n' "$extra" "$acct_json" "$error" "$pj" "$diag_json" "$(date +%s)" > "$USAGE_FILE"
    return 1
  }

  claude_is_running() {
    local last_line
    last_line=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | awk 'NF{line=$0} END{print line}')
    [ -z "$last_line" ] && return 1
    [[ ! "$last_line" =~ \$[[:space:]]*$ ]]
  }

  send_usage_and_wait() {
    $TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
    sleep 0.5
    if $TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "How is Claude doing"; then
      $TMUX_BIN send-keys -t "$SESSION" "0" 2>/dev/null
      sleep 1
    fi
    $TMUX_BIN send-keys -t "$SESSION" "/usage" 2>/dev/null
    sleep 0.5
    $TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
    sleep 0.3
    $TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null

    local MAX_ATTEMPTS=30
    local attempt=0
    while [ $attempt -lt $MAX_ATTEMPTS ]; do
      if [ $attempt -lt 15 ]; then sleep 0.2; else sleep 1; fi
      attempt=$((attempt + 1))
      content=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
      if echo "$content" | grep -q "% used"; then return 0; fi
      if echo "$content" | tail -5 | grep -q "Status dialog dismissed"; then return 2; fi
      if echo "$content" | grep -q "Failed to load usage data"; then
        if echo "$content" | grep -q "rate_limit_error"; then return 0; fi
        return 1
      fi
    done
    return 1
  }

  # Build the Claude launch command
  local claude_cmd=""
  if [ -n "$ACCT_TOKEN" ]; then
    claude_cmd="CLAUDE_CODE_OAUTH_TOKEN='$ACCT_TOKEN' CLAUDE_USAGE_MON=1 $CLAUDE --dangerously-skip-permissions"
  else
    claude_cmd="unset ANTHROPIC_API_KEY && CLAUDE_USAGE_MON=1 $CLAUDE --dangerously-skip-permissions"
  fi

  # --- Phase: session ---
  write_phase "session"
  local created_session=false
  if ! $TMUX_BIN has-session -t "$SESSION" 2>/dev/null; then
    $TMUX_BIN new-session -d -s "$SESSION" -x 200 -y 50 -c "$HOME"
    created_session=true
  fi

  # --- Phase: claude ---
  write_phase "claude"

  local pane
  pane=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null)
  if echo "$pane" | grep -q "trust this folder"; then
    $TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null
    sleep 3
  fi

  if $created_session || ! claude_is_running; then
    write_phase "start"
    if ! $created_session; then
      $TMUX_BIN send-keys -t "$SESSION" C-c 2>/dev/null
      sleep 0.3
    fi
    $TMUX_BIN send-keys -t "$SESSION" "$claude_cmd" Enter
    # Clear scrollback to hide token from tmux history
    sleep 1
    $TMUX_BIN clear-history -t "$SESSION" 2>/dev/null
    for attempt in 1 2 3 4 5 6; do
      sleep 2
      pane=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null)
      if echo "$pane" | grep -q "trust this folder"; then
        $TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null
        sleep 3
        break
      fi
      if echo "$pane" | grep -qE "^❯"; then break; fi
    done
    if ! claude_is_running; then
      local diag
      diag=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -v '^$' | tail -10)
      write_error_with_diag "claude_start_failed" "$diag"
      return 1
    fi
  fi

  # --- Phase: send + wait ---
  write_phase "send"
  write_phase "wait"
  send_usage_and_wait
  local wait_rc=$?

  if [ $wait_rc -eq 2 ]; then
    write_phase "restart"
    $TMUX_BIN kill-session -t "$SESSION" 2>/dev/null
    sleep 1
    $TMUX_BIN new-session -d -s "$SESSION" -x 200 -y 50 -c "$HOME"
    $TMUX_BIN send-keys -t "$SESSION" "$claude_cmd" Enter
    sleep 1
    $TMUX_BIN clear-history -t "$SESSION" 2>/dev/null
    for attempt in 1 2 3 4 5 6; do
      sleep 2
      pane=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null)
      if echo "$pane" | grep -q "trust this folder"; then
        $TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null
        sleep 3
        break
      fi
      if echo "$pane" | grep -qE "^❯"; then break; fi
    done
    if claude_is_running; then
      send_usage_and_wait
      wait_rc=$?
    fi
  fi

  if [ $wait_rc -eq 1 ]; then
    local diag
    diag=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -v '^$' | tail -10)
    $TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
    write_error_with_diag "usage_unavailable" "$diag"
    return 1
  fi

  # --- Phase: parse ---
  write_phase "parse"

  local PHASES_JSON="["
  local first=true
  for p in "${PHASES[@]}"; do
    $first && first=false || PHASES_JSON+=","
    PHASES_JSON+="\"$p\""
  done
  PHASES_JSON+="]"

  export POLL_PHASES="$PHASES_JSON"
  export USAGE_LOG
  export PREV_USAGE_DATA=""
  [[ -f "$USAGE_FILE" ]] && PREV_USAGE_DATA=$(cat "$USAGE_FILE" 2>/dev/null)

  $TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
    | python3 -c '
import re, json, sys, time, os
from datetime import datetime, timedelta, timezone
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo

lines = sys.stdin.read().split("\n")
phases = json.loads(os.environ.get("POLL_PHASES", "[]"))
result = {"ts": int(time.time()), "phases": phases}

prev = {}
try:
    prev = json.loads(os.environ.get("PREV_USAGE_DATA", "{}"))
except (json.JSONDecodeError, TypeError):
    pass

def parse_reset_ts(text):
    m2 = re.search(r"Resets (\w+) (\d+) at (\d+)(?::(\d+))?(am|pm)(?:\s*\(([^)]+)\))?", text)
    if m2:
        month_str, day, hour, minute_str, ampm = m2.group(1), int(m2.group(2)), int(m2.group(3)), m2.group(4), m2.group(5)
        tz_name = m2.group(6)
        minute = int(minute_str) if minute_str else 0
        if ampm == "pm" and hour != 12: hour += 12
        elif ampm == "am" and hour == 12: hour = 0
        months = {"Jan":1,"Feb":2,"Mar":3,"Apr":4,"May":5,"Jun":6,"Jul":7,"Aug":8,"Sep":9,"Oct":10,"Nov":11,"Dec":12}
        month = months.get(month_str, 1)
        tz = None
        if tz_name:
            try: tz = ZoneInfo(tz_name)
            except: pass
        now = datetime.now(tz) if tz else datetime.now()
        year = now.year
        if tz: reset = datetime(year, month, day, hour, minute, 0, tzinfo=tz)
        else: reset = datetime(year, month, day, hour, minute, 0)
        if reset < now - timedelta(days=1):
            if tz: reset = datetime(year + 1, month, day, hour, minute, 0, tzinfo=tz)
            else: reset = datetime(year + 1, month, day, hour, minute, 0)
        return int(reset.timestamp())
    m = re.search(r"Resets (\d+)(?::(\d+))?(am|pm)(?:\s*\(([^)]+)\))?", text)
    if not m: return None
    hour = int(m.group(1))
    minute = int(m.group(2)) if m.group(2) else 0
    ampm = m.group(3)
    tz_name = m.group(4)
    if ampm == "pm" and hour != 12: hour += 12
    elif ampm == "am" and hour == 12: hour = 0
    tz = None
    if tz_name:
        try: tz = ZoneInfo(tz_name)
        except: pass
    now = datetime.now(tz) if tz else datetime.now()
    reset = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if reset <= now:
        if (now - reset).total_seconds() < 600: return int(reset.timestamp())
        reset += timedelta(days=1)
    return int(reset.timestamp())

def parse_reset_relative(text):
    m = re.search(r"Resets in (?:(\d+)d\s*)?(?:(\d+)h\s*)?(?:(\d+)m)?", text, re.IGNORECASE)
    if not m or not any(m.groups()): return None
    days  = int(m.group(1)) if m.group(1) else 0
    hours = int(m.group(2)) if m.group(2) else 0
    mins  = int(m.group(3)) if m.group(3) else 0
    total_secs = days * 86400 + hours * 3600 + mins * 60
    return int(time.time()) + total_secs if total_secs > 0 else None

def find_reset(lines, i):
    for k in range(i + 1, min(i + 7, len(lines))):
        ts = parse_reset_ts(lines[k])
        if ts: return ts
        ts = parse_reset_relative(lines[k])
        if ts: return ts
    return None

session_pct = None; session_reset_ts = None
weekly_pct  = None; weekly_reset_ts  = None

for i, line in enumerate(lines):
    match = re.search(r"(\d+)% used", line)
    if not match: continue
    pct_val = int(match.group(1))
    label = ""
    for j in range(i - 1, max(i - 3, -1), -1):
        lbl = lines[j].strip()
        if lbl and "\u2588" not in lbl and "\u258c" not in lbl and "% used" not in lbl:
            label = lbl; break
    label_lower = label.lower()
    if "session" in label_lower and session_pct is None:
        session_pct = pct_val; session_reset_ts = find_reset(lines, i)
    elif "week" in label_lower and weekly_pct is None:
        weekly_pct = pct_val; weekly_reset_ts = find_reset(lines, i)

if session_pct is not None and session_reset_ts is not None:
    result["pct"] = session_pct; result["reset_ts"] = session_reset_ts
if weekly_pct is not None: result["weekly_pct"] = weekly_pct
if weekly_reset_ts is not None: result["weekly_reset_ts"] = weekly_reset_ts

if "pct" not in result:
    full = "\n".join(lines)
    if "rate_limit_error" in full:
        result["pct"] = 100; result["weekly_pct"] = 100; result["rate_limited"] = True
        log_file = os.environ.get("USAGE_LOG", "")
        if log_file and os.path.exists(log_file):
            now = int(time.time())
            with open(log_file) as f:
                for raw in reversed(f.read().strip().split("\n")):
                    try:
                        entry = json.loads(raw)
                        if entry.get("reset_ts", 0) > now and "reset_ts" not in result:
                            result["reset_ts"] = entry["reset_ts"]
                        if entry.get("weekly_reset_ts", 0) > now and "weekly_reset_ts" not in result:
                            result["weekly_reset_ts"] = entry["weekly_reset_ts"]
                        if "reset_ts" in result:
                            if "weekly_reset_ts" in result or "weekly_reset_ts" not in entry: break
                    except: continue
    elif "OAuth token does not meet scope requirement" in full or "permission_error" in full:
        result["error"] = "oauth_scope_error"
    elif "Status dialog dismissed" in full:
        result["error"] = "usage_unavailable"; result["error_detail"] = "dialog dismissed"
        result["diag"] = [l.rstrip() for l in lines if l.strip()][-15:]
    elif "Failed to load usage data" in full:
        result["error"] = "usage_unavailable"; result["error_detail"] = "API error"
        result["diag"] = [l.rstrip() for l in lines if l.strip()][-15:]
    else:
        result["error"] = "parse_failed"
        result["diag"] = [l.rstrip() for l in lines if l.strip()][-15:]
    for key in ("pct", "reset_ts", "weekly_pct", "weekly_reset_ts"):
        if key not in result and key in prev: result[key] = prev[key]

print(json.dumps(result))

if "pct" in result and "reset_ts" in result:
    log_file = os.environ.get("USAGE_LOG", "")
    if log_file:
        WINDOW_HOURS = 5
        window_dur = WINDOW_HOURS * 3600
        window_start = result["reset_ts"] - window_dur
        elapsed = result["ts"] - window_start
        window_elapsed_pct = round(min(elapsed / window_dur * 100, 100), 1)
        budget_delta = round(result["pct"] - window_elapsed_pct, 1)
        window_id = datetime.fromtimestamp(result["reset_ts"]).strftime("%Y-%m-%dT%H:%M")
        elapsed_h = elapsed / 3600
        burn_rate = round(result["pct"] / elapsed_h, 2) if elapsed_h > 0.1 else None
        entry = {"ts": result["ts"], "pct": result["pct"], "reset_ts": result["reset_ts"],
                 "window_id": window_id, "window_elapsed_pct": window_elapsed_pct, "budget_delta": budget_delta}
        if burn_rate is not None: entry["burn_rate"] = burn_rate
        if "weekly_pct" in result: entry["weekly_pct"] = result["weekly_pct"]
        if "weekly_reset_ts" in result:
            wrt = result["weekly_reset_ts"]; entry["weekly_reset_ts"] = wrt
            entry["weekly_window_id"] = datetime.fromtimestamp(wrt).strftime("%Y-W%W")
            WEEKLY_DUR = 7 * 24 * 3600
            w_elapsed = result["ts"] - (wrt - WEEKLY_DUR)
            entry["weekly_elapsed_pct"] = round(min(w_elapsed / WEEKLY_DUR * 100, 100), 1)
            if "weekly_pct" in result:
                entry["weekly_budget_delta"] = round(result["weekly_pct"] - entry["weekly_elapsed_pct"], 1)
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        with open(log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
' > "$USAGE_FILE"

  # Close the usage panel
  $TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
}

# ── Main dispatch ───────────────────────────────────────

accounts=$(discover_accounts)

if [ -z "$accounts" ]; then
  # No accounts configured — legacy single-account mode
  poll_account "" ""
else
  # Multi-account: poll all in parallel
  while IFS=$'\t' read -r acct_name acct_token; do
    poll_account "$acct_name" "$acct_token" &
  done <<< "$accounts"
  wait
fi
