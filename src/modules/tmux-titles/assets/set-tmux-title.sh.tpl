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

        pct=$(echo "$marker" | sed -n 's/.*\$pct:[[:space:]]*\([0-9]*\).*/\1/p')
        q_raw=$(echo "$marker" | sed -n 's/.*\$q:[[:space:]]*\([soh][+?-]\).*/\1/p')
        model="${q_raw:0:1}"
        quality="${q_raw:1:1}"

        session=$({{tmux}} display-message -p '#{session_name}' 2>/dev/null)
        if [[ -n "$session" ]]; then
            mkdir -p "$TOPICS_DIR"

            # Write JSON for VS Code extension (atomic write via temp+mv)
            tmp="$TOPICS_DIR/.${session}.tmp"
            target="$TOPICS_DIR/${session}.json"
            printf '{"topic":"%s","ts":%d}\n' "$topic" "$(date +%s)" > "$tmp"
            mv -f "$tmp" "$target"

            # Per-session turn counter (incremented once per Stop hook fire)
            counter_file="$TOPICS_DIR/.${session}.turn"
            turn=$(( $(cat "$counter_file" 2>/dev/null || echo 0) + 1 ))
            echo "$turn" > "$counter_file"

            # Append to JSONL log for model/quality analysis. This is timeline data,
            # so it lives under the persistent (reinstall-surviving) state dir.
            marker_log="{{state_dir}}/marker-log.jsonl"
            # One-time migration from the old ~/.config/claude-toolkit/marker-log.jsonl.
            old_marker_log="$(dirname "$TOPICS_DIR")/marker-log.jsonl"
            if [[ -f "$old_marker_log" && ! -f "$marker_log" ]]; then
                mkdir -p "$(dirname "$marker_log")"
                mv "$old_marker_log" "$marker_log" 2>/dev/null || true
            fi
            mkdir -p "$(dirname "$marker_log")"
            printf '{"ts":%d,"session":"%s","turn":%d,"topic":"%s","m":"%s","pct":%s,"q":"%s"}\n' \
                "$(date +%s)" "$session" "$turn" "$topic" \
                "${model:-?}" "${pct:--1}" "${quality:-?}" \
                >> "$marker_log"
        fi
    fi
fi

exit 0
