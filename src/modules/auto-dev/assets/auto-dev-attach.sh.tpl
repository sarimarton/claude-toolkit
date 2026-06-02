#!/bin/sh
# auto-dev-attach.sh — Open Terminal.app and attach to the runner's tmux session.
# Usage: auto-dev-attach.sh <session_name>
export PATH="{{home}}/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

SESS="$1"
[[ -z "$SESS" ]] && exit 1

TMUX_BIN={{tmux}}

# Select the window running ./run.sh (the actual runner), in case earlier
# clicks left orphan zsh windows in the session.
RUNNER_WIN=$("$TMUX_BIN" list-windows -t "$SESS" -F '#{window_index} #{window_name}' 2>/dev/null \
  | awk '$2 ~ /run\.sh/ {print $1; exit}')
TARGET="$SESS"
[[ -n "$RUNNER_WIN" ]] && TARGET="$SESS:$RUNNER_WIN"

osascript <<ASEOF
tell application "Terminal"
  activate
  do script "$TMUX_BIN attach -t $TARGET"
end tell
ASEOF
