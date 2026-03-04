#!/bin/bash
# Claude Code Notification hook
# Receives JSON on stdin with .message, .title, .cwd fields
# Uses terminal-notifier for clickable notifications.
# On click: Hammerspoon focuses the Ghostty tab or opens a new one.

HS="{{hs}}"

input=$(cat)
message=$(echo "$input" | {{jq}} -r '.message // ""')
title=$(echo "$input" | {{jq}} -r '.title // "Claude Code"')
cwd=$(echo "$input" | {{jq}} -r '.cwd // ""')

[ -z "$message" ] && exit 0

# Skip notifications from the usage monitor session
[[ "$CLAUDE_USAGE_MON" == "1" ]] && exit 0

pane="$TMUX_PANE"

if [[ -n "$TMUX" && -n "$pane" ]]; then
    session_name=$({{tmux}} display-message -t "$pane" -p '#{session_name}' 2>/dev/null)
fi

subtitle="${cwd##*/}"

args=(
    -title "$title"
    -message "$message"
    -group "${pane:-claude}"
)
[[ -n "$subtitle" ]] && args+=(-subtitle "$subtitle")
[[ -n "$session_name" ]] && args+=(-execute "$HS -c \"require('claude-sessions').focusOrAttach('$session_name')\"")

terminal-notifier "${args[@]}"
