#!/bin/sh
# auto-dev-attach.sh — Open Terminal.app and attach to the runner's tmux session.
# Usage: auto-dev-attach.sh <session_name>
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

SESS="$1"
[[ -z "$SESS" ]] && exit 1

TMUX_BIN={{tmux}}
osascript <<ASEOF
tell application "Terminal"
  activate
  do script "$TMUX_BIN attach -t $SESS"
end tell
ASEOF
