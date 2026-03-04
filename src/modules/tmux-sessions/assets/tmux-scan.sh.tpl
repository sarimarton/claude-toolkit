#!/bin/bash
# Scan tmux sessions for Claude Code panes.
# Handles session group deduplication and Claude Code detection.
# Output: structured data per pane for LLM summarization.

HOME_DIR="{{home}}"
SEP="~~~"

# Get unique base sessions (deduplicate session groups)
{{tmux}} list-sessions -F '#{?session_group,#{session_group},#{session_name}} #{session_name}' 2>/dev/null \
  | sort -t' ' -k1,1 -u \
  | while read -r _group session; do

  {{tmux}} list-panes -s -t "$session" -F "#{window_index} #{pane_pid} #{pane_current_path}" 2>/dev/null \
    | while read -r winidx pid dir; do
    [ -z "$winidx" ] && continue

    pane="${session}:${winidx}.0"
    proc=$(ps -p "$pid" -o args= 2>/dev/null)
    short_dir=$(echo "$dir" | sed "s|${HOME_DIR}|~|")

    # Determine process type
    if echo "$proc" | grep -q 'claude'; then
      proc_type="claude"
    else
      proc_type=$(echo "$proc" | sed 's/ .*//' | sed 's|.*/||; s/^-//')
    fi

    # Capture pane buffer once, reuse for all extractions
    buffer=$({{tmux}} capture-pane -t "$pane" -p -S -300 2>/dev/null)

    # Extract topic marker (if any)
    marker=$(echo "$buffer" | grep '(\$topic:' | tail -1)

    # Capture last visible lines for context
    tail_lines=$({{tmux}} capture-pane -t "$pane" -p 2>/dev/null | grep -v '^$' | tail -5)

    # For non-claude panes, extract last shell command from buffer
    last_cmd=""
    if [ "$proc_type" != "claude" ]; then
      last_cmd=$(echo "$buffer" | grep '\$ .' | sed 's/.*\$ //' | tail -1)
    fi

    echo "PANE: ${session}:${winidx} [${proc_type}] ${short_dir}"
    [ -n "$marker" ] && echo "MARKER: ${marker}"
    [ -n "$last_cmd" ] && echo "LASTCMD: ${last_cmd}"
    echo "VISIBLE:"
    echo "$tail_lines"
    echo "$SEP"
  done
done
