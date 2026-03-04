#!/bin/bash
# Fast tmux session scanner — zero LLM calls.
# Uses tmux format variables + buffer grep for $topic/$next markers.
# Output: ;-separated, same format as tmux-sessions.sh --raw.

HOME_DIR="{{home}}"

# Deduplicate session groups: pick one session per group
{{tmux}} list-sessions -F '#{?session_group,#{session_group},#{session_name}} #{session_name}' 2>/dev/null \
  | sort -t' ' -k1,1 -u \
  | while read -r _group session; do

  {{tmux}} list-panes -s -t "$session" \
    -F "#{window_index}	#{pane_current_command}	#{pane_current_path}	#{pane_title}	#{pane_pid}" 2>/dev/null \
    | while IFS=$'\t' read -r winidx cmd dir title pid; do
    [ -z "$winidx" ] && continue

    pane_id="${session}:${winidx}"
    short_dir=$(echo "$dir" | sed "s|${HOME_DIR}|~|")

    # Detect process type
    if echo "$cmd" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      proc="claude"
    else
      proc="$cmd"
    fi

    # Try to extract $topic/$next marker from buffer (no LLM)
    marker=$({{tmux}} capture-pane -t "${pane_id}.0" -p -S -300 2>/dev/null | grep '(\$topic:' | tail -1)

    if [ -n "$marker" ]; then
      # Parse marker: ($topic: X | $next: Y) or ($topic: X)
      topic=$(echo "$marker" | sed 's/.*\$topic: *//; s/ *|.*//')
      next=$(echo "$marker" | grep -o '\$next: *[^)]*' | sed 's/\$next: *//')
      [ -z "$next" ] && next="-"
    else
      # Fallback: use pane_title from Claude Code OSC
      # Strip spinner prefix
      topic=$(echo "$title" | sed 's/^[⠁⠂⠃⠄⠅⠆⠇⠈⠉⠊⠋⠌⠍⠎⠏⠐⠑⠒⠓⠔⠕⠖⠗⠘⠙⠚⠛⠜⠝⠞⠟⠠⠡⠢⠣⠤⠥⠦⠧⠨⠩⠪⠫⠬⠭⠮⠯⠰⠱⠲⠳⠴⠵⠶⠷⠸⠹⠺⠻⠼⠽⠾⠿✳✱] *//')
      # Decode status from spinner prefix
      if echo "$title" | grep -q '^[⠁⠂⠃⠄⠅⠆⠇⠈⠉⠊⠋⠌⠍⠎⠏⠐⠑⠒⠓⠔⠕⠖⠗⠘⠙⠚⠛⠜⠝⠞⠟⠠⠡⠢⠣⠤⠥⠦⠧⠨⠩⠪⠫⠬⠭⠮⠯⠰⠱⠲⠳⠴⠵⠶⠷⠸⠹⠺⠻⠼⠽⠾⠿]'; then
        next="aktív"
      else
        next="idle"
      fi
      [ -z "$topic" ] && topic="$short_dir"
    fi

    echo "${pane_id}; ${proc}; ${short_dir}; ${topic}; ${next}"
  done
done
