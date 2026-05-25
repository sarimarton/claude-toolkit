#!/bin/bash
# Stop hook: extract $topic marker from pane buffer and set terminal tab title.
# Renames the tmux window for fzf-choose and other tmux-level tools,
# and writes a JSON file for the VS Code terminal-topic extension.

[[ -z "$TMUX" ]] && exit 0
[[ -n "$DICTATION_HOOK_RUNNING" ]] && exit 0

TOPICS_DIR="{{install_dir}}/topics"

marker=$({{tmux}} capture-pane -p -S -100 2>/dev/null | grep '(\$topic:' | tail -1)

if [[ -n "$marker" ]]; then
    topic=$(echo "$marker" | sed 's/.*\$topic: *//; s/ *|.*//')
    if [[ -n "$topic" ]]; then
        {{tmux}} rename-window "✻ $topic" 2>/dev/null

        model=$(echo "$marker" | sed -n 's/.*\$m:[[:space:]]*\([soh]\).*/\1/p')
        pct=$(echo "$marker" | sed -n 's/.*\$pct:[[:space:]]*\([0-9]*\).*/\1/p')
        quality=$(echo "$marker" | sed -n 's/.*\$q:[[:space:]]*\([+?-]\).*/\1/p')

        session=$({{tmux}} display-message -p '#{session_name}' 2>/dev/null)
        if [[ -n "$session" ]]; then
            mkdir -p "$TOPICS_DIR"

            # Write JSON for VS Code extension (atomic write via temp+mv)
            tmp="$TOPICS_DIR/.${session}.tmp"
            target="$TOPICS_DIR/${session}.json"
            printf '{"topic":"%s","ts":%d}\n' "$topic" "$(date +%s)" > "$tmp"
            mv -f "$tmp" "$target"

            # Append to JSONL log for model/quality analysis
            log_dir="$(dirname "$TOPICS_DIR")"
            printf '{"ts":%d,"session":"%s","topic":"%s","m":"%s","pct":%s,"q":"%s"}\n' \
                "$(date +%s)" "$session" "$topic" \
                "${model:-?}" "${pct:--1}" "${quality:-?}" \
                >> "$log_dir/marker-log.jsonl"
        fi
    fi
fi

exit 0
