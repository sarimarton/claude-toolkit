#!/usr/bin/env bash
# Click/drag handler for the tmux status-right scrollbar.
# Converts a mouse event on the bar into a copy-mode scroll jump, with
# auto-enter-copy-mode on click and single-flight throttling for drag.
#
# Bind in tmux.conf (the bar occupies the rightmost `bar_width` columns of
# status-right):
#
#   bind -T root MouseDown1StatusRight \
#     run -b "~/.config/claude-toolkit/scripts/scrollbar-click.sh down \
#        #{mouse_x} #{client_width} #{history_size} #{pane_id}"
#
#   bind -T root MouseDrag1StatusRight \
#     run -b "~/.config/claude-toolkit/scripts/scrollbar-click.sh drag \
#        #{mouse_x} #{client_width} #{history_size} #{pane_id}"
#
# Args: action mouse_x client_width history_size pane_id [bar_width=30]
#   action = down | drag
#
# Layout: the bar reads LEFT=top of scrollback, RIGHT=bottom (most recent).
# scroll_position=0 means at the very bottom; =history_size means at top.
#
# Throttling: a flock single-flight gate per pane. If another instance is
# running, the new invocation queues its target into a state file and exits;
# the running instance drains the queue before releasing the lock — so the
# final mouse position is always processed even under high drag rates.

set -uo pipefail

action="${1:?down|drag}"
mouse_x="${2:?mouse_x}"
client_width="${3:?client_width}"
history_size="${4:?history_size}"
pane_id="${5:?pane_id}"
bar_width="${6:-30}"

[ "$history_size" -le 0 ] && exit 0

# Per-pane lock + queue file. The lock is a directory (mkdir is atomic on
# POSIX); stale locks (>2s old) are reaped lazily so a crashed script
# doesn't permanently break the bind.
slug="${pane_id//%/}"
lock_dir="${TMPDIR:-/tmp}/scrollbar-click-${slug}.lock.d"
queue_file="${TMPDIR:-/tmp}/scrollbar-click-${slug}.queue"

# Always record the latest position into the queue (atomic via mv).
printf '%s %s %s %s\n' "$action" "$mouse_x" "$client_width" "$history_size" \
  > "${queue_file}.tmp"
mv "${queue_file}.tmp" "$queue_file"

# Reap stale lock (more than 2 seconds old).
if [ -d "$lock_dir" ]; then
  lock_age=$(( $(date +%s) - $(stat -f '%c' "$lock_dir" 2>/dev/null || echo 0) ))
  [ "$lock_age" -gt 2 ] && rmdir "$lock_dir" 2>/dev/null || true
fi

# Try to acquire the lock; if another process holds it, exit (it will pick
# up our queued position before releasing).
mkdir "$lock_dir" 2>/dev/null || exit 0
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM

apply_jump() {
  local act="$1" mx="$2" cw="$3" hs="$4"
  [ "$hs" -le 0 ] && return 0

  local bar_left=$((cw - bar_width))
  local relative=$((mx - bar_left))
  if [ "$relative" -lt 0 ] || [ "$relative" -ge "$bar_width" ]; then
    return 0
  fi

  local target=$((hs * (bar_width - 1 - relative) / (bar_width - 1)))
  [ "$target" -lt 0 ] && target=0
  [ "$target" -gt "$hs" ] && target=$hs

  local in_mode
  in_mode=$(tmux display -p -t "$pane_id" '#{pane_in_mode}' 2>/dev/null || echo 0)

  local current
  if [ "$in_mode" = "0" ]; then
    # Drag never enters copy-mode — only an explicit click does.
    [ "$act" = "drag" ] && return 0
    tmux copy-mode -t "$pane_id" 2>/dev/null || return 0
    current=0
  else
    current=$(tmux display -p -t "$pane_id" '#{scroll_position}' 2>/dev/null || echo 0)
  fi

  local diff=$((target - current))
  if [ "$diff" -gt 0 ]; then
    tmux send-keys -X -t "$pane_id" -N "$diff" scroll-up 2>/dev/null || true
  elif [ "$diff" -lt 0 ]; then
    tmux send-keys -X -t "$pane_id" -N $((-diff)) scroll-down 2>/dev/null || true
  fi
}

# Drain queue: process the latest target until no new events arrive.
while [ -f "$queue_file" ]; do
  read -r q_action q_mx q_cw q_hs < "$queue_file"
  rm -f "$queue_file"
  apply_jump "$q_action" "$q_mx" "$q_cw" "$q_hs"
done
