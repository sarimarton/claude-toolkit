#!/bin/bash
# VS Code terminal → tmux integration
#
# LINKED=true  — grouped sessions: tabs share window list (old default)
#                killing a window won't close the VS Code tab
# LINKED=false — independent sessions: each tab = own session (like Ghostty)
#                killing the session closes the VS Code tab
LINKED=false

BASE="${VSCODE_TMUX_SESSION:-vscode}"
BASE="${BASE//\./-}"

# --claude flag: start claude instead of zsh (used by tmux-claude profile)
CLAUDE=false
[[ "$1" == "--claude" ]] && CLAUDE=true

if [[ "$LINKED" == true ]]; then
    SESSION="$BASE"
    cleanup_dead_linked() {
        {{tmux}} ls -F '#{session_name} #{session_attached}' 2>/dev/null \
            | grep "^${SESSION}_" \
            | awk '$2 == "0" { print $1 }' \
            | xargs -I{} {{tmux}} kill-session -t {}
    }
    if {{tmux}} has-session -t "$SESSION" 2>/dev/null; then
        cleanup_dead_linked
        LINKED_NAME="${SESSION}_$$"
        {{tmux}} new-session -d -t "$SESSION" -s "$LINKED_NAME"
        if $CLAUDE; then
            {{tmux}} new-window -t "$LINKED_NAME" /bin/zsh -ic claude
        else
            {{tmux}} new-window -t "$LINKED_NAME"
        fi
        exec {{tmux}} attach-session -t "$LINKED_NAME"
    else
        if $CLAUDE; then
            exec {{tmux}} new-session -s "$SESSION" /bin/zsh -ic claude
        else
            exec {{tmux}} new-session -s "$SESSION"
        fi
    fi
else
    SESSION="${BASE}_$$"
    if $CLAUDE; then
        exec {{tmux}} new-session -s "$SESSION" 'zsh -ic claude'
    else
        exec {{tmux}} new-session -s "$SESSION"
    fi
fi
