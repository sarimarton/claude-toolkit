#!/bin/bash
# Play a sound unless running in headless (claude -p) mode.
# Usage: play-sound.sh <sound-file>
# Walks up the process tree to detect if the claude CLI was invoked with -p.

sound_file="${1:?Usage: play-sound.sh <sound-file>}"

# The Notification event fires on idle ("Claude is waiting for your input"),
# not only on real prompts. Skip those so only actual questions ring.
if [ ! -t 0 ]; then
  input=$(cat)
  if [ -n "$input" ]; then
    message=$(echo "$input" | /usr/bin/jq -r '.message // ""' 2>/dev/null)
    [[ "$message" == *"waiting for your input"* ]] && exit 0
  fi
fi

pid=$PPID
for _ in 1 2 3 4; do
  args=$(ps -o args= -p "$pid" 2>/dev/null) || break
  # Match "claude -p" as a standalone flag (not inside --dangerously-skip-permissions etc.)
  if [[ "$args" =~ claude[[:space:]]+-p([[:space:]]|$) ]]; then
    exit 0
  fi
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ -z "$pid" || "$pid" == "1" ]] && break
done

afplay "$sound_file" &
