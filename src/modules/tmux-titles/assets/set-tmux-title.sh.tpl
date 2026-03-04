#!/bin/bash
# Stop hook: extract $topic marker from pane buffer and set terminal tab title.
# Renames the tmux window for fzf-choose and other tmux-level tools,
# and writes a JSON file for the VS Code terminal-topic extension.

[[ -z "$TMUX" ]] && exit 0
[[ -n "$DICTATION_HOOK_RUNNING" ]] && exit 0

TOPICS_DIR="{{home}}/.config/vscode-terminal-topic/topics"

marker=$({{tmux}} capture-pane -p -S -100 2>/dev/null | grep '(\$topic:' | tail -1)

if [[ -n "$marker" ]]; then
    topic=$(echo "$marker" | sed 's/.*\$topic: *//; s/ *|.*//')
    if [[ -n "$topic" ]]; then
        {{tmux}} rename-window "$topic" 2>/dev/null

        # Write JSON for VS Code extension (atomic write via temp+mv)
        session=$({{tmux}} display-message -p '#{session_name}' 2>/dev/null)
        if [[ -n "$session" ]]; then
            mkdir -p "$TOPICS_DIR"
            tmp="$TOPICS_DIR/.${session}.tmp"
            target="$TOPICS_DIR/${session}.json"
            printf '{"topic":"%s","ts":%d}\n' "$topic" "$(date +%s)" > "$tmp"
            mv -f "$tmp" "$target"
        fi
    fi
fi

exit 0
