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

# Self-lock: prevent concurrent poll-script invocations from racing on the same
# claude_usage_mon tmux session. The swiftbar plugin already gates auto-polls
# with the same lock file, but Refresh now and any other manual trigger bypass
# that gate, so we acquire it here as well.
LOCK_FILE="/tmp/claude-usage-poll.lock"
acquire_lock() {
  if ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    return 0
  fi
  local held; held=$(cat "$LOCK_FILE" 2>/dev/null)
  # If the swiftbar wrapper wrote its own PID, treat it as ours and overwrite
  if [ "$held" = "$PPID" ]; then
    echo "$$" > "$LOCK_FILE"
    return 0
  fi
  if [ -n "$held" ] && kill -0 "$held" 2>/dev/null; then
    return 1
  fi
  # Stale lock — remove and retry once
  rm -f "$LOCK_FILE"
  ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null
  [ "$(cat "$LOCK_FILE" 2>/dev/null)" = "$$" ]
}
if ! acquire_lock; then
  exit 0
fi
trap 'rm -f "$LOCK_FILE"' EXIT

TMUX_BIN={{tmux}}
CLAUDE={{claude}}
CONFIG_FILE="{{config_file}}"
USAGE_DIR="{{home}}/.local/share/claude-usage"
STALE_RESTART_THRESHOLD=600  # seconds; if error has persisted longer, kill stuck tmux session
MAX_SESSION_LIFETIME=7200    # seconds; cap monitor session age (defense in depth vs userland leaks in long-running claude proc)

# ── Account discovery ───────────────────────────────────
YQ={{yq}}

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
    local RAW_LOG="/tmp/claude-usage-raw.log"
  else
    local SESSION="claude_usage_mon_${ACCT_NAME}"
    local USAGE_FILE="/tmp/claude-usage-${ACCT_NAME}.json"
    local USAGE_LOG="$USAGE_DIR/usage-${ACCT_NAME}.jsonl"
    local RAW_LOG="/tmp/claude-usage-raw-${ACCT_NAME}.log"
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
    local prev_pct="" prev_reset="" prev_weekly="" prev_weekly_reset="" prev_last_success="" prev_lost_since=""
    if [ -f "$USAGE_FILE" ]; then
      { read -r prev_pct; read -r prev_reset; read -r prev_weekly; read -r prev_weekly_reset; read -r prev_last_success; read -r prev_lost_since; } < <(python3 -c "
import json
try:
    d=json.load(open('$USAGE_FILE'))
    print(d.get('pct','')); print(d.get('reset_ts','')); print(d.get('weekly_pct','')); print(d.get('weekly_reset_ts','')); print(d.get('last_success_ts','')); print(d.get('reset_ts_lost_since',''))
except: print(); print(); print(); print(); print(); print()
" 2>/dev/null) || true
    fi
    local extra=""
    [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
    [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
    [ -n "$prev_weekly" ] && extra+="\"weekly_pct\":$prev_weekly,"
    [ -n "$prev_weekly_reset" ] && extra+="\"weekly_reset_ts\":$prev_weekly_reset,"
    [ -n "$prev_last_success" ] && extra+="\"last_success_ts\":$prev_last_success,"
    [ -n "$prev_lost_since" ] && extra+="\"reset_ts_lost_since\":$prev_lost_since,"
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
    local prev_pct="" prev_reset="" prev_weekly="" prev_weekly_reset="" prev_err_since="" prev_ts="" prev_last_success="" prev_lost_since=""
    if [ -f "$USAGE_FILE" ]; then
      { read -r prev_pct; read -r prev_reset; read -r prev_weekly; read -r prev_weekly_reset; read -r prev_err_since; read -r prev_ts; read -r prev_last_success; read -r prev_lost_since; } < <(python3 -c "
import json
try:
    d=json.load(open('$USAGE_FILE'))
    print(d.get('pct','')); print(d.get('reset_ts','')); print(d.get('weekly_pct','')); print(d.get('weekly_reset_ts',''))
    print(d.get('error_since_ts') or ''); print(d.get('ts') or ''); print(d.get('last_success_ts','')); print(d.get('reset_ts_lost_since',''))
except: print(); print(); print(); print(); print(); print(); print(); print()
" 2>/dev/null) || true
    fi
    local extra=""
    [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
    [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
    [ -n "$prev_weekly" ] && extra+="\"weekly_pct\":$prev_weekly,"
    [ -n "$prev_weekly_reset" ] && extra+="\"weekly_reset_ts\":$prev_weekly_reset,"
    [ -n "$prev_last_success" ] && extra+="\"last_success_ts\":$prev_last_success,"
    [ -n "$prev_lost_since" ] && extra+="\"reset_ts_lost_since\":$prev_lost_since,"
    local err_since="$prev_err_since"
    [ -z "$err_since" ] && err_since="${prev_ts:-$(date +%s)}"
    extra+="\"error_since_ts\":$err_since,"
    local acct_json=""
    [ -n "$ACCT_NAME" ] && acct_json="\"account\":\"$ACCT_NAME\","
    printf '{%s%s"error":"%s","phases":[%s],"diag":%s,"ts":%d}\n' "$extra" "$acct_json" "$error" "$pj" "$diag_json" "$(date +%s)" > "$USAGE_FILE"
    return 1
  }

  claude_is_running() {
    # Positive detection: Claude Code is running iff
    #   (a) the pane's foreground command is NOT a plain shell, AND
    #   (b) at least one Claude UI marker is visible in the pane content.
    # Earlier heuristic was negative ("last line not ending in $ ") which produced
    # false positives for any non-bash prompt (zsh %, custom PS1, error messages,
    # …) — that caused /usage to be sent into a dead/empty shell, looping the
    # poll into usage_unavailable without ever rebuilding the Claude session.
    local cmd content
    cmd=$($TMUX_BIN list-panes -t "$SESSION" -F '#{pane_current_command}' 2>/dev/null | head -1)
    # Negative process-name filter: if the foreground command is a plain shell,
    # Claude is definitely not running. We do NOT positive-match on "claude" or
    # "node" because the actual foreground command varies — Claude spawns MCP
    # children (npm exec, …) and tmux reports the most-recent foreground child,
    # which is often an MCP package name (e.g. "2.1.132"). So we only reject the
    # known-bad cases (shell process names) here, then let the content check do
    # the heavy lifting.
    case "$cmd" in
      ""|zsh|-zsh|bash|-bash|sh|-sh|fish|-fish) return 1 ;;
    esac
    # Content check: at least one Claude UI marker must be visible.
    # ❯ — Claude prompt char (U+276F); ⏵⏵ — bypass-mode indicator (U+23F5);
    # "bypass permissions" — status-bar text when launched with --dangerously-skip-permissions.
    # We require both ASCII and unicode markers in the alternation so it still
    # matches even if the ❯ character is mis-encoded by tmux capture-pane.
    content=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null)
    [ -z "$content" ] && return 1
    if printf '%s' "$content" | grep -qE '^❯|bypass permissions|⏵⏵'; then
      return 0
    fi
    return 1
  }

  send_usage_and_wait() {
    # Low-level capture via pipe-pane instead of capture-pane.
    #
    # capture-pane only reads tmux's *settled* screen grid. Current Claude Code
    # paints the "Current session"/"Current week" usage block and then overwrites
    # it within the same render burst, so by the time capture-pane reads the grid
    # the block is already gone — it is invisible to any capture-pane poll, no
    # matter how fast. pipe-pane instead streams every byte the program writes to
    # the pane (all intermediate renders included), so the block lands in the raw
    # log even when it only flashes for a single frame. The block reliably
    # repaints on every tab switch, so we nudge the Usage tab to force it out.
    #
    # The raw log is truncated per call, so it never carries stale cross-poll data
    # — that removes the need for the old clear-history + "Refreshing" guards.
    : > "$RAW_LOG"
    $TMUX_BIN pipe-pane -t "$SESSION" "cat >> '$RAW_LOG'" 2>/dev/null

    # Reset input state: C-u wipes any residual prompt text without cycling the
    # Claude UI mode. Escape used to be safe here, but the current UI interprets
    # Escape on an empty prompt as "open Rewind/agent panel", which silently
    # opens the wrong panel and breaks the /usage submission entirely.
    $TMUX_BIN send-keys -t "$SESSION" C-u 2>/dev/null
    sleep 0.3
    if $TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "How is Claude doing"; then
      $TMUX_BIN send-keys -t "$SESSION" "0" 2>/dev/null
      sleep 1
    fi
    # Literal-mode burst (-l): deliver "/usage" as one chunk of characters.
    # Claude UI only opens its autocomplete dropdown on character-by-character
    # typing — burst delivery skips that, so Enter submits "/usage" directly
    # as a slash command. The old per-key send opened the dropdown, and from
    # there neither Escape+Enter (clears input → "Flowing… stop hooks") nor
    # Tab+Enter (mode-cycle on fresh sessions → opens the wrong panel) reliably
    # resolved the slash command.
    $TMUX_BIN send-keys -l -t "$SESSION" "/usage" 2>/dev/null
    sleep 0.3
    $TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null

    # Acquisition loop: poll the raw log (not the grid). Each iteration nudges the
    # Usage tab with Right/Left — transiting through Usage repaints the block,
    # which pipe-pane captures even though we immediately leave the tab. Robust to
    # whichever tab /usage happens to open on.
    local MAX_SECONDS=12
    local start=$SECONDS
    local rc=1
    while [ $(( SECONDS - start )) -lt $MAX_SECONDS ]; do
      # The percent and the word "used" are printed at separate columns, so in the
      # raw stream a cursor-move escape (e.g. \x1b[58G, itself containing digits)
      # sits between them — a literal "% used" never matches. Allow any bytes in
      # between instead.
      if grep -aq "Current session" "$RAW_LOG" 2>/dev/null && grep -aqE '[0-9]+%.{0,20}used' "$RAW_LOG" 2>/dev/null; then
        rc=0; break
      fi
      if grep -aq "Failed to load usage data" "$RAW_LOG" 2>/dev/null; then
        grep -aq "rate_limit_error" "$RAW_LOG" 2>/dev/null && rc=0 || rc=1
        break
      fi
      # Only treat a dismissal as fatal once it is the latest thing on screen
      # (a stale "dialog dismissed" line from before /usage must not abort us).
      if $TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | tail -5 | grep -qE "(Status|Settings) dialog dismissed"; then
        rc=2; break
      fi
      # Nudge: re-enter the Usage tab to trigger a repaint.
      $TMUX_BIN send-keys -t "$SESSION" Right 2>/dev/null
      $TMUX_BIN send-keys -t "$SESSION" Left 2>/dev/null
      sleep 0.25
    done
    $TMUX_BIN pipe-pane -t "$SESSION" 2>/dev/null   # stop raw capture
    return $rc
  }

  # Build the Claude launch command
  local claude_cmd=""
  if [ -n "$ACCT_TOKEN" ]; then
    claude_cmd="CLAUDE_CODE_OAUTH_TOKEN='$ACCT_TOKEN' CLAUDE_USAGE_MON=1 $CLAUDE --dangerously-skip-permissions"
  else
    claude_cmd="unset ANTHROPIC_API_KEY && CLAUDE_USAGE_MON=1 $CLAUDE --dangerously-skip-permissions"
  fi

  # Lifetime cap: kill the monitor session every MAX_SESSION_LIFETIME seconds even
  # when healthy. The claude process inside the session is long-running and may
  # accumulate userland RSS — periodic recreate bounds the leak window.
  if $TMUX_BIN has-session -t "$SESSION" 2>/dev/null; then
    local sess_created; sess_created=$($TMUX_BIN display-message -t "$SESSION" -p '#{session_created}' 2>/dev/null)
    if [ -n "$sess_created" ] && [ "$sess_created" -gt 0 ] 2>/dev/null; then
      if [ $(( $(date +%s) - sess_created )) -gt $MAX_SESSION_LIFETIME ]; then
        $TMUX_BIN kill-session -t "$SESSION" 2>/dev/null
      fi
    fi
  fi

  # Watchdog: kill the tmux session if it has been failing or silently producing
  # stale data for too long. Three triggers:
  #   1. error_since_ts older than threshold (explicit failures: dismissed, parse_failed, …)
  #   2. last_success_ts older than threshold (no real parse — covers the silent-fallback case
  #      where the parser returned a stale pct without an error mező)
  #   3. reset_ts_lost_since older than threshold (partial-parse loop: pct keeps being
  #      scraped from scrollback but the Resets line never reappears — covers the
  #      "Settings dialog dismissed" loop that masquerades as success)
  if [ -f "$USAGE_FILE" ]; then
    local err_since last_success lost_since
    { read -r err_since; read -r last_success; read -r lost_since; } < <(python3 -c "
import json
try:
    d = json.load(open('$USAGE_FILE'))
    print(d.get('error_since_ts') or '')
    print(d.get('last_success_ts') or '')
    print(d.get('reset_ts_lost_since') or '')
except:
    print(''); print(''); print('')
" 2>/dev/null) || true
    local now_ts; now_ts=$(date +%s)
    if [ -n "$err_since" ] && [ $(( now_ts - err_since )) -gt $STALE_RESTART_THRESHOLD ]; then
      $TMUX_BIN kill-session -t "$SESSION" 2>/dev/null
    elif [ -n "$last_success" ] && [ $(( now_ts - last_success )) -gt $STALE_RESTART_THRESHOLD ]; then
      $TMUX_BIN kill-session -t "$SESSION" 2>/dev/null
    elif [ -n "$lost_since" ] && [ $(( now_ts - lost_since )) -gt $STALE_RESTART_THRESHOLD ]; then
      $TMUX_BIN kill-session -t "$SESSION" 2>/dev/null
    fi
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

  python3 -c '
import re, json, sys, time, os
from datetime import datetime, timedelta, timezone
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo

# Input is the raw PTY stream captured by pipe-pane, not a settled grid. Normalize
# it: a cursor column-move (ESC[<n>G) becomes a space so "45%" and "used" — which
# the client prints at separate columns — stay separable; remaining CSI/charset
# escapes are stripped; CR becomes NL; progress-bar glyphs collapse to a space.
_raw = sys.stdin.read()
_raw = re.sub(r"\x1b\[[0-9]+G", " ", _raw)
_raw = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", _raw)
_raw = re.sub(r"\x1b[()][AB0]", "", _raw)
_raw = _raw.replace("\r", "\n")
_bar = re.compile(r"[█▌▊▉▏▎▍▋▐░▒▓]+")
lines = [_bar.sub(" ", ln) for ln in _raw.split("\n")]
phases = json.loads(os.environ.get("POLL_PHASES", "[]"))
result = {"ts": int(time.time()), "phases": phases}
parse_warnings = []

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
            try:
                tz = ZoneInfo(tz_name)
            except Exception:
                parse_warnings.append(f"tz_unknown:{tz_name}")
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
        try:
            tz = ZoneInfo(tz_name)
        except Exception:
            parse_warnings.append(f"tz_unknown:{tz_name}")
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

def find_reset(lines, i, max_offset_secs=None):
    # max_offset_secs: drop implausibly far parses (e.g. session reset rolled +1 day
    # by parse_reset_ts when the time-only string already passed >10 min ago).
    now_ts = int(time.time())
    # Wider lookahead (10 lines) — Anthropic may interleave the Resets line with
    # extra metadata rows (cache info, sub-tier breakdowns, etc.); a 6-line
    # window has already been hit once when the layout grew.
    for k in range(i + 1, min(i + 11, len(lines))):
        ts = parse_reset_ts(lines[k])
        if ts is None:
            ts = parse_reset_relative(lines[k])
        if ts is None:
            continue
        if max_offset_secs is not None and ts - now_ts > max_offset_secs:
            continue
        return ts
    return None

session_pct = None; session_reset_ts = None
weekly_pct  = None; weekly_reset_ts  = None

# The raw stream is a chronological concatenation of every render the client
# emitted during the poll (the tab-nudge loop typically produces several full
# repaints). We walk it forwards keyed on the section label and, for each label,
# take the first "<n>% used" that follows it \u2014 then clear the label so the
# "Usage credits" bar (which also prints "% used" but is a different metric)
# cannot be misattributed. Forward iteration overwrites earlier renders, so we
# naturally settle on the values from the LAST (most recent) repaint.
cur = None
for i, line in enumerate(lines):
    if "Current session" in line: cur = "s"; continue
    if "Current week" in line: cur = "w"; continue
    if "Usage credits" in line: cur = None; continue
    if cur is None: continue
    match = re.search(r"(\d+)%\s*used", line)
    if not match: continue
    pct_val = int(match.group(1))
    if cur == "s":
        # Session windows are 5h \u2014 cap to 5h 30min to filter day-rollover bugs
        session_pct = pct_val; session_reset_ts = find_reset(lines, i, max_offset_secs=5*3600+1800)
    else:
        weekly_pct = pct_val; weekly_reset_ts = find_reset(lines, i)
    cur = None

if session_pct is not None:
    result["pct"] = session_pct
    result["last_success_ts"] = result["ts"]
    if session_reset_ts is not None:
        result["reset_ts"] = session_reset_ts
if weekly_pct is not None: result["weekly_pct"] = weekly_pct
if weekly_reset_ts is not None: result["weekly_reset_ts"] = weekly_reset_ts

# Partial-parse fallback: pct was extracted but the Resets line drifted past the
# 6-line find_reset window (or rendered late). Without this, the menu loses its
# "(Xh Ym)" remaining display even though pct itself is valid.
now_ts_partial = int(time.time())
if "pct" in result and "reset_ts" not in result and isinstance(prev.get("reset_ts"), (int, float)):
    val = prev["reset_ts"]
    if val > now_ts_partial and val - now_ts_partial <= 5*3600 + 1800:
        result["reset_ts"] = val
if "weekly_pct" in result and "weekly_reset_ts" not in result and isinstance(prev.get("weekly_reset_ts"), (int, float)):
    val = prev["weekly_reset_ts"]
    if val > now_ts_partial:
        result["weekly_reset_ts"] = val

# Track partial-parse persistence: bash watchdog uses this to kill a stuck session
# that keeps producing pct from scrollback but never a fresh Resets line.
if "pct" in result and "reset_ts" not in result:
    result["reset_ts_lost_since"] = prev.get("reset_ts_lost_since") or result["ts"]

if "pct" not in result:
    full = "\n".join(lines)
    if "rate_limit_error" in full:
        result["pct"] = 100; result["weekly_pct"] = 100; result["rate_limited"] = True
        result["last_success_ts"] = result["ts"]  # rate-limit is a valid parse
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
    elif "Status dialog dismissed" in full or "Settings dialog dismissed" in full:
        result["error"] = "usage_unavailable"; result["error_detail"] = "dialog dismissed"
        result["diag"] = [l.rstrip() for l in lines if l.strip()][-15:]
    elif "Failed to load usage data" in full:
        result["error"] = "usage_unavailable"; result["error_detail"] = "API error"
        result["diag"] = [l.rstrip() for l in lines if l.strip()][-15:]
    else:
        result["error"] = "parse_failed"
        result["diag"] = [l.rstrip() for l in lines if l.strip()][-15:]
    now_ts_fallback = int(time.time())
    # Preserve last_success_ts so the watchdog can detect "no real parse for N seconds"
    if "last_success_ts" in prev:
        result["last_success_ts"] = prev["last_success_ts"]
    for key in ("pct", "reset_ts", "weekly_pct", "weekly_reset_ts"):
        if key in result or key not in prev: continue
        val = prev[key]
        # Skip stale or implausibly far session reset_ts (e.g. day-rollover bug)
        if key == "reset_ts":
            if not isinstance(val, (int, float)) or val < now_ts_fallback or val - now_ts_fallback > 5*3600 + 1800:
                continue
        result[key] = val

# Track error persistence so the bash watchdog can restart a stuck session.
# A successful poll has no error key, so error_since_ts is naturally absent.
if result.get("error"):
    result["error_since_ts"] = prev.get("error_since_ts") or prev.get("ts") or int(time.time())

if parse_warnings:
    # Deduplicate while preserving order
    seen = set()
    result["warnings"] = [w for w in parse_warnings if not (w in seen or seen.add(w))]

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
' < "$RAW_LOG" > "$USAGE_FILE"

  # Close the usage panel
  $TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
}

# ── Main dispatch ───────────────────────────────────────

# Distinguish three cases:
#  1. No config file → legacy single-account mode
#  2. Config OK, no .accounts → legacy single-account mode
#  3. Config exists but is malformed → surface the error, do NOT silently fall back
accounts=""
config_error=""
if [ -f "$CONFIG_FILE" ]; then
  # Note: no `-e` — a comments-only YAML evaluates to `null`, which `-e` would
  # treat as failure. Without `-e`, yq returns non-zero only on real syntax errors.
  if ! $YQ '.' "$CONFIG_FILE" >/dev/null 2>&1; then
    config_error="config_parse_failed"
  else
    accounts=$($YQ -r '.accounts[]? | .name + "\t" + .token' "$CONFIG_FILE" 2>/dev/null)
  fi
fi

if [ -n "$config_error" ]; then
  # Surface the malformed-config error in the default USAGE_FILE so the
  # swiftbar plugin shows ⚠ instead of silently displaying stale data.
  now_ts=$(date +%s)
  printf '{"ts":%d,"error":"%s","error_detail":"yq could not parse %s","error_since_ts":%d}\n' \
    "$now_ts" "$config_error" "$CONFIG_FILE" "$now_ts" > /tmp/claude-usage.json
  exit 1
fi

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
