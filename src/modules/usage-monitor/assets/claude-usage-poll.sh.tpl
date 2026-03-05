#!/usr/bin/env bash
# claude-usage-poll.sh — Query Claude Code /usage via a dedicated tmux session
#
# Maintains a dedicated "claude_usage_mon" tmux session with an idle Claude
# instance. Every invocation sends /usage, captures, parses, and writes JSON.
#
# Output: /tmp/claude-usage.json  (session percentage + minutes until reset)
# Tracks phases for real-time display in the Hammerspoon menubar.

set -uo pipefail
unset TMUX

TMUX_BIN={{tmux}}
USAGE_FILE="/tmp/claude-usage.json"
USAGE_LOG="{{home}}/.local/share/claude-usage/usage.jsonl"
SESSION="claude_usage_mon"
CLAUDE={{claude}}

PHASES=()

# Write current phase to the usage file (for real-time menubar updates)
# Preserves previous pct/mins_left so the menubar can keep showing stale data
# while revalidation is in progress (stale-while-revalidate pattern).
write_phase() {
  PHASES+=("$1")
  local pj=""
  for p in "${PHASES[@]}"; do
    [ -n "$pj" ] && pj+=","
    pj+="\"$p\""
  done
  # Carry forward cached pct/reset_ts/weekly_pct from the existing file
  local prev_pct="" prev_reset="" prev_weekly=""
  if [ -f "$USAGE_FILE" ]; then
    prev_pct=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('pct',''))" 2>/dev/null)
    prev_reset=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('reset_ts',''))" 2>/dev/null)
    prev_weekly=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('weekly_pct',''))" 2>/dev/null)
  fi
  local extra=""
  [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
  [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
  [ -n "$prev_weekly" ] && extra+="\"weekly_pct\":$prev_weekly,"
  printf '{%s"phase":"%s","phases":[%s],"ts":%d}\n' "$extra" "$1" "$pj" "$(date +%s)" > "$USAGE_FILE"
}

# Write error with diagnostic pane content and exit.
# Preserves cached pct/mins_left so the menubar can keep showing stale data (SWR).
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
  # Carry forward cached pct/reset_ts/weekly_pct (stale-while-revalidate)
  local prev_pct="" prev_reset="" prev_weekly=""
  if [ -f "$USAGE_FILE" ]; then
    prev_pct=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('pct',''))" 2>/dev/null)
    prev_reset=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('reset_ts',''))" 2>/dev/null)
    prev_weekly=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('weekly_pct',''))" 2>/dev/null)
  fi
  local extra=""
  [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
  [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
  [ -n "$prev_weekly" ] && extra+="\"weekly_pct\":$prev_weekly,"
  printf '{%s"error":"%s","phases":[%s],"diag":%s,"ts":%d}\n' "$extra" "$error" "$pj" "$diag_json" "$(date +%s)" > "$USAGE_FILE"
  exit 1
}

# Detect whether Claude is running by inspecting pane content.
# Empty pane or shell prompt (ends with $) means Claude is not running.
claude_is_running() {
  local last_line
  last_line=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | awk 'NF{line=$0} END{print line}')
  # Empty pane = nothing running
  [ -z "$last_line" ] && return 1
  # Shell prompt pattern = Claude exited
  [[ ! "$last_line" =~ \$[[:space:]]*$ ]]
}

# --- Phase: session ---
write_phase "session"
created_session=false
if ! $TMUX_BIN has-session -t "$SESSION" 2>/dev/null; then
  $TMUX_BIN new-session -d -s "$SESSION" -x 200 -y 50 -c "$HOME"
  created_session=true
fi

# --- Phase: claude ---
write_phase "claude"
if $created_session || ! claude_is_running; then
  write_phase "start"
  if ! $created_session; then
    # Kill any leftover shell process
    $TMUX_BIN send-keys -t "$SESSION" C-c 2>/dev/null
    sleep 0.3
  fi
  # Default ~/.claude is OAuth (no apiKeyHelper) — unset env var as safety net
  $TMUX_BIN send-keys -t "$SESSION" "unset ANTHROPIC_API_KEY && CLAUDE_USAGE_MON=1 $CLAUDE --dangerously-skip-permissions" Enter
  sleep 3
  # Accept workspace trust dialog if present (Enter confirms the default "Yes" selection)
  if $TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "trust this folder"; then
    $TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null
  fi
  sleep 5
  if ! claude_is_running; then
    diag=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -v '^$' | tail -10)
    write_error_with_diag "claude_start_failed" "$diag"
  fi
fi

# --- Phase: send ---
write_phase "send"
$TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
sleep 0.5
# Dismiss feedback dialog if present ("How is Claude doing this session?")
if $TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "How is Claude doing"; then
  $TMUX_BIN send-keys -t "$SESSION" "0" 2>/dev/null
  sleep 1
fi
# Type "/usage", dismiss autocomplete with Escape, then Enter to execute.
$TMUX_BIN send-keys -t "$SESSION" "/usage" 2>/dev/null
sleep 0.5
$TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
sleep 0.3
$TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null

# --- Phase: wait ---
# Poll pane content until data appears, error is detected, or timeout.
# No aggressive retries — if the API is down, accept it gracefully.
write_phase "wait"
MAX_WAIT=15
elapsed=0
while [ $elapsed -lt $MAX_WAIT ]; do
  sleep 2
  elapsed=$((elapsed + 2))
  content=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
  # Success: usage data loaded
  if echo "$content" | grep -q "% used"; then
    break
  fi
  # API error: don't retry, just report it.
  # Rate limit errors go to parse phase (handled as pct=100 there).
  if echo "$content" | grep -q "Failed to load usage data"; then
    if echo "$content" | grep -q "rate_limit_error"; then
      break  # let parser handle it
    fi
    diag=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -v '^$' | tail -10)
    $TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
    write_error_with_diag "usage_unavailable" "$diag"
  fi
done

# --- Phase: parse ---
write_phase "parse"

# Build phases JSON for the Python parser
PHASES_JSON="["
first=true
for p in "${PHASES[@]}"; do
  $first && first=false || PHASES_JSON+=","
  PHASES_JSON+="\"$p\""
done
PHASES_JSON+="]"
export POLL_PHASES="$PHASES_JSON"
export USAGE_LOG

$TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null \
  | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
  | python3 -c '
import re, json, sys, time, os
from datetime import datetime, timedelta

lines = sys.stdin.read().split("\n")
phases = json.loads(os.environ.get("POLL_PHASES", "[]"))
result = {"ts": int(time.time()), "phases": phases}

def parse_reset_ts(text):
    """Parse "Resets 4pm" or "Resets 4:30pm" → epoch timestamp."""
    m = re.search(r"Resets (\d+)(?::(\d+))?(am|pm)", text)
    if not m:
        return None
    hour = int(m.group(1))
    minute = int(m.group(2)) if m.group(2) else 0
    ampm = m.group(3)
    if ampm == "pm" and hour != 12: hour += 12
    elif ampm == "am" and hour == 12: hour = 0
    now = datetime.now()
    reset = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if reset <= now:
        if (now - reset).total_seconds() < 600:
            return int(reset.timestamp())
        reset += timedelta(days=1)
    return int(reset.timestamp())

def parse_reset_relative(text):
    """Parse "Resets in 3d 4h" or "Resets in 2h 30m" → epoch timestamp."""
    m = re.search(r"Resets in (?:(\d+)d\s*)?(?:(\d+)h\s*)?(?:(\d+)m)?", text, re.IGNORECASE)
    if not m or not any(m.groups()):
        return None
    days  = int(m.group(1)) if m.group(1) else 0
    hours = int(m.group(2)) if m.group(2) else 0
    mins  = int(m.group(3)) if m.group(3) else 0
    total_secs = days * 86400 + hours * 3600 + mins * 60
    return int(time.time()) + total_secs if total_secs > 0 else None

def find_reset(lines, i):
    """Search up to 7 lines forward for a reset timestamp."""
    for k in range(i + 1, min(i + 7, len(lines))):
        ts = parse_reset_ts(lines[k])
        if ts: return ts
        ts = parse_reset_relative(lines[k])
        if ts: return ts
    return None

# Scan all "% used" lines — collect session and weekly data
session_pct = None; session_reset_ts = None
weekly_pct  = None; weekly_reset_ts  = None

for i, line in enumerate(lines):
    match = re.search(r"(\d+)% used", line)
    if not match:
        continue
    pct_val = int(match.group(1))
    # Walk backwards to find the section label
    label = ""
    for j in range(i - 1, max(i - 3, -1), -1):
        lbl = lines[j].strip()
        if lbl and "\u2588" not in lbl and "\u258c" not in lbl and "% used" not in lbl:
            label = lbl
            break
    label_lower = label.lower()
    if "session" in label_lower and session_pct is None:
        session_pct = pct_val
        session_reset_ts = find_reset(lines, i)
    elif "week" in label_lower and weekly_pct is None:
        weekly_pct = pct_val
        weekly_reset_ts = find_reset(lines, i)

# Emit session data (require reset_ts to avoid orphaned pct)
if session_pct is not None and session_reset_ts is not None:
    result["pct"] = session_pct
    result["reset_ts"] = session_reset_ts
if weekly_pct is not None:
    result["weekly_pct"] = weekly_pct
if weekly_reset_ts is not None:
    result["weekly_reset_ts"] = weekly_reset_ts

if "pct" not in result:
    full = "\n".join(lines)
    if "rate_limit_error" in full:
        # Rate limited = weekly budget exhausted → pct=100, weekly_pct=100
        result["pct"] = 100
        result["weekly_pct"] = 100
        result["rate_limited"] = True
        log_file = os.environ.get("USAGE_LOG", "")
        if log_file and os.path.exists(log_file):
            now = int(time.time())
            with open(log_file) as f:
                for raw in reversed(f.read().strip().split("\n")):
                    try:
                        entry = json.loads(raw)
                        if entry.get("reset_ts", 0) > now:
                            result["reset_ts"] = entry["reset_ts"]
                        if entry.get("weekly_reset_ts", 0) > now and "weekly_reset_ts" not in result:
                            result["weekly_reset_ts"] = entry["weekly_reset_ts"]
                        if "reset_ts" in result:
                            break
                    except (json.JSONDecodeError, KeyError):
                        continue
    elif "OAuth token does not meet scope requirement" in full or "permission_error" in full:
        result["error"] = "oauth_scope_error"
    elif "Failed to load usage data" in full or "Status dialog dismissed" in full:
        result["error"] = "usage_unavailable"
        non_empty = [l.rstrip() for l in lines if l.strip()]
        result["diag"] = non_empty[-15:]
    else:
        result["error"] = "parse_failed"
        non_empty = [l.rstrip() for l in lines if l.strip()]
        result["diag"] = non_empty[-15:]

print(json.dumps(result))

# Append to long-term JSONL log (only on successful parse with pct + reset_ts)
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
        # Burn rate: session % consumed per elapsed hour in window
        elapsed_h = elapsed / 3600
        burn_rate = round(result["pct"] / elapsed_h, 2) if elapsed_h > 0.1 else None
        entry = {
            "ts": result["ts"],
            "pct": result["pct"],
            "reset_ts": result["reset_ts"],
            "window_id": window_id,
            "window_elapsed_pct": window_elapsed_pct,
            "budget_delta": budget_delta,
        }
        if burn_rate is not None:
            entry["burn_rate"] = burn_rate
        # Weekly fields
        if "weekly_pct" in result:
            entry["weekly_pct"] = result["weekly_pct"]
        if "weekly_reset_ts" in result:
            wrt = result["weekly_reset_ts"]
            entry["weekly_reset_ts"] = wrt
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
