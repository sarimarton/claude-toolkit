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
  # Carry forward cached pct/reset_ts from the existing file
  local prev_pct="" prev_reset=""
  if [ -f "$USAGE_FILE" ]; then
    prev_pct=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('pct',''))" 2>/dev/null)
    prev_reset=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('reset_ts',''))" 2>/dev/null)
  fi
  local extra=""
  [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
  [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
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
  # Carry forward cached pct/reset_ts (stale-while-revalidate)
  local prev_pct="" prev_reset=""
  if [ -f "$USAGE_FILE" ]; then
    prev_pct=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('pct',''))" 2>/dev/null)
    prev_reset=$(python3 -c "import json; d=json.load(open('$USAGE_FILE')); print(d.get('reset_ts',''))" 2>/dev/null)
  fi
  local extra=""
  [ -n "$prev_pct" ] && extra+="\"pct\":$prev_pct,"
  [ -n "$prev_reset" ] && extra+="\"reset_ts\":$prev_reset,"
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
  $TMUX_BIN new-session -d -s "$SESSION" -x 200 -y 50
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
  $TMUX_BIN send-keys -t "$SESSION" "CLAUDE_USAGE_MON=1 $CLAUDE --dangerously-skip-permissions" Enter
  sleep 8
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
# Type "/usage" first, let autocomplete appear, then Enter to select & execute.
# send-keys must NOT include Enter with the text — autocomplete needs time to match.
$TMUX_BIN send-keys -t "$SESSION" "/usage" 2>/dev/null
sleep 1
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
  # API error: don't retry, just report it
  if echo "$content" | grep -q "Failed to load usage data"; then
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

$TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null \
  | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
  | python3 -c '
import re, json, sys, time, os
from datetime import datetime, timedelta

lines = sys.stdin.read().split("\n")
phases = json.loads(os.environ.get("POLL_PHASES", "[]"))
result = {"ts": int(time.time()), "phases": phases}

def parse_reset_ts(text):
    """Parse "Resets 4pm" or "Resets 4:30pm" and return epoch timestamp of next reset."""
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

for i, line in enumerate(lines):
    match = re.search(r"(\d+)% used", line)
    if not match:
        continue
    pct = int(match.group(1))
    # Walk backwards to find label
    label = ""
    for j in range(i - 1, max(i - 3, -1), -1):
        label = lines[j].strip()
        if label and "\u2588" not in label and "\u258c" not in label and "% used" not in label:
            break
    if "session" not in label.lower():
        continue
    # Search up to 6 lines forward for "Resets" (handles extra blank lines)
    reset_ts = None
    for k in range(i + 1, min(i + 7, len(lines))):
        reset_ts = parse_reset_ts(lines[k])
        if reset_ts is not None:
            break
    # Only emit pct if we also found the reset time (prevents orphaned pct without time)
    if reset_ts is not None:
        result["pct"] = pct
        result["reset_ts"] = reset_ts
    break  # only need session

if "pct" not in result:
    full = "\n".join(lines)
    if "OAuth token does not meet scope requirement" in full or "permission_error" in full:
        result["error"] = "oauth_scope_error"
    elif "Failed to load usage data" in full or "Status dialog dismissed" in full:
        result["error"] = "usage_unavailable"
        non_empty = [l.rstrip() for l in lines if l.strip()]
        result["diag"] = non_empty[-15:]
    else:
        result["error"] = "parse_failed"
        # Include last non-empty lines as diagnostic
        non_empty = [l.rstrip() for l in lines if l.strip()]
        result["diag"] = non_empty[-15:]

print(json.dumps(result))
' > "$USAGE_FILE"

# Close the usage panel
$TMUX_BIN send-keys -t "$SESSION" Escape 2>/dev/null
