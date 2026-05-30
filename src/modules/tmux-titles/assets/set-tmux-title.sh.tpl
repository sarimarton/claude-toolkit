#!/bin/bash
# Stop hook: extract $topic marker from pane buffer and set terminal tab title.
# Renames the tmux window for fzf-choose and other tmux-level tools,
# and writes a JSON file for the VS Code terminal-topic extension.

[[ -z "$TMUX" ]] && exit 0
[[ -n "$DICTATION_HOOK_RUNNING" ]] && exit 0

TOPICS_DIR="{{install_dir}}/topics"

# Stop-hook stdin carries the Claude session UUID (session_id) and cwd as JSON.
# We record these so the menu can resume a session that a reboot/crash left dead.
payload=$(cat 2>/dev/null)
claude_uuid=$(printf '%s' "$payload" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//; s/"$//')
claude_cwd=$(printf '%s' "$payload" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"//; s/"$//')

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

            # Resume index: tmux-resurrect restores the "✻ topic" window after a
            # reboot, but Claude itself is gone. Record session→UUID here so the
            # menu can offer an on-demand resume. Keyed by (session, UUID) on write
            # — one row per Claude session, refreshing its current window-name —
            # and matched by (session, window-name) on recovery, which works because
            # the row always carries the latest $topic, the same value resurrect
            # restores into the window name. Lives under the persistent state dir so
            # it survives the reboot it exists to recover from.
            if [[ -n "$claude_uuid" ]]; then
                resume_index="{{state_dir}}/resume-index.tsv"
                win_name="✻ $topic"
                [[ -z "$claude_cwd" ]] && claude_cwd=$({{tmux}} display-message -p '#{pane_current_path}' 2>/dev/null)
                mkdir -p "$(dirname "$resume_index")"
                tmp_idx="$resume_index.$$.tmp"
                awk -F'\t' -v s="$session" -v u="$claude_uuid" '!($1==s && $3==u)' "$resume_index" 2>/dev/null > "$tmp_idx"
                printf '%s\t%s\t%s\t%s\t%s\n' "$session" "$win_name" "$claude_uuid" "$claude_cwd" "$(date +%s)" >> "$tmp_idx"
                mv -f "$tmp_idx" "$resume_index"
            fi
        fi
    fi
fi

exit 0
