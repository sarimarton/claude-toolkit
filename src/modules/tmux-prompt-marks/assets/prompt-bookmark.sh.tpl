#!/usr/bin/env bash
# Bookmark menu + jump handler for tmux-prompt-marks.
#
# The companion zsh hook (prompt-marks.zsh) records (counter, total_lines,
# command_summary) into a per-pane state file on every preexec. This script
# either renders that file as a tmux display-menu, or jumps the pane's
# copy-mode viewport to a bookmarked position.
#
# Bind in tmux.conf:
#   bind -T prefix b run -b "~/.config/tmux/prompt-bookmark.sh menu #{pane_id}"
#
# Usage:
#   prompt-bookmark.sh menu <pane_id>
#   prompt-bookmark.sh jump <pane_id> <saved_total_lines>

set -uo pipefail

action="${1:?menu|jump}"
pane_id="${2:?pane_id}"

state_dir="${HOME}/.config/claude-toolkit/state"
slug="${pane_id//%/}"
file="${state_dir}/bookmarks-${slug}"

case "$action" in
  menu)
    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
      tmux display-message "No bookmarks yet for $pane_id"
      exit 0
    fi

    # tmux's run-shell PATH is minimal; pull in Homebrew where fzf-tmux lives.
    export PATH="/opt/homebrew/bin:$PATH"
    if ! command -v fzf-tmux >/dev/null 2>&1; then
      tmux display-message "fzf-tmux required for bookmark menu (brew install fzf)"
      exit 0
    fi

    SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    # Build items: <saved_h>\t#<n>  <cmd_summary>  (chronological, last 20).
    # Field 1 (saved_h) is hidden via --with-nth 2 but accessed by `{1}` in
    # the focus binding to drive the live jump.
    items=$(awk -F'\t' '{printf "%s\t#%s  %s\n", $2, $1, $3}' <(tail -n 20 "$file"))

    # Top-anchored 30%-tall popup so the bottom 70% of the target pane stays
    # visible — that is where the scroll-up effect lands. `start:last` puts
    # the cursor on the most recent bookmark (bottom of the chronological
    # list) and triggers the first focus event → the first jump happens
    # automatically. `focus:execute-silent` re-runs the jump on every
    # arrow-key motion (live preview).
    # `--layout=reverse` makes the prompt sit at the top with items
    # growing downward — without it, fzf's default "bottom-up" rendering
    # would visually invert our chronological input (newest would end up
    # at the top, oldest at the bottom).
    fzf-tmux -p 95%,30% \
      --layout=reverse \
      --delimiter $'\t' \
      --with-nth 2 \
      --no-sort \
      --prompt "bookmark ❯ " \
      --header "↑↓=live preview · type=filter · enter=keep · esc=cancel" \
      --bind "start:last" \
      --bind "focus:execute-silent($SCRIPT jump $pane_id {1})" \
      <<< "$items" >/dev/null || true
    ;;

  jump)
    saved_h="${3:?saved_total_lines}"
    current_h=$(tmux display -p -t "$pane_id" '#{e|+:#{history_size},#{pane_height}}' 2>/dev/null) || exit 0
    history_size=$(tmux display -p -t "$pane_id" '#{history_size}' 2>/dev/null) || exit 0
    diff=$((current_h - saved_h))

    if [[ $diff -le 0 ]]; then
      tmux display-message "Already at or before bookmark"
      exit 0
    fi
    if [[ $diff -gt $history_size ]]; then
      diff=$history_size
    fi

    in_mode=$(tmux display -p -t "$pane_id" '#{pane_in_mode}' 2>/dev/null || echo 0)
    if [[ "$in_mode" = "0" ]]; then
      tmux copy-mode -t "$pane_id" 2>/dev/null || exit 0
      current=0
    else
      current=$(tmux display -p -t "$pane_id" '#{scroll_position}' 2>/dev/null || echo 0)
    fi

    target_diff=$((diff - current))
    if [[ $target_diff -gt 0 ]]; then
      tmux send-keys -X -t "$pane_id" -N "$target_diff" scroll-up 2>/dev/null || true
    elif [[ $target_diff -lt 0 ]]; then
      tmux send-keys -X -t "$pane_id" -N $((-target_diff)) scroll-down 2>/dev/null || true
    fi
    ;;

  *)
    echo "usage: $0 menu <pane_id> | jump <pane_id> <saved_total_lines>" >&2
    exit 1
    ;;
esac
