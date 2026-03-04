#!/usr/bin/env bash
# claude-attach.sh — Attach to a detached Claude session by opening a new Ghostty tab.
# Uses the same signal file mechanism as the Hammerspoon version.
# Usage: claude-attach.sh <session_name>

SESSION="$1"
[[ -z "$SESSION" ]] && exit 1

ATTACH_SIGNAL="/tmp/.ghostty-attach"

# Write signal file for ghostty-tmux.sh to pick up
echo "$SESSION" > "$ATTACH_SIGNAL"

# Activate Ghostty and open a new tab (or launch it if not running)
if pgrep -qf "Ghostty"; then
    osascript -e 'tell application "Ghostty" to activate' 2>/dev/null
    sleep 0.2
    osascript -e 'tell application "System Events" to tell process "Ghostty" to keystroke "t" using command down' 2>/dev/null
else
    open -a Ghostty
fi
