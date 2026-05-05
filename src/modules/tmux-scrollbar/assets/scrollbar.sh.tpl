#!/usr/bin/env bash
# Sub-pixel scrollbar a tmux status-rightba copy-mode alatt.
# 3 külön #() shell call hívja, mert a tmux 3.x a #() shell outputban a
# #[reverse]...#[noreverse] szekvenciát NEM értelmezi (literálisan beilleszti).
# A REVERSE switchet a status-format-ban kell csinálni a from-partial karakter
# köré. Lásd a tmux.conf status-right beállítását.
#
# Args: MODE pos total pagesize [width=30]
#   MODE = prefix | thumb-start | suffix
#
# Algoritmus:
#   - 8 sub-pixel cellánként
#   - thumb_size_subpx = pagesize / total * total_subpx, MIN cap 8 (1 karakter)
#   - from_subpx = (scroll_max - pos) / scroll_max * (total_subpx - thumb_size)
#   - to_subpx = from + thumb_size
#
#   prefix       → ' ' * from_cell
#   thumb-start  → 1 karakter, REVERSE keretben:
#                    full from cell (from_offset=0)  → ' '  (REV space = fehér cella)
#                    partial from cell               → blocks[8 - from_offset]
#                                                      (REV bal-aligned = jobb-aligned)
#   suffix       → middle full + to-partial + trailing space-ek

set -euo pipefail
mode="${1:?prefix|thumb-start|suffix}"
pos="${2:-0}"
total="${3:-1}"
pagesize="${4:-1}"
width="${5:-30}"

if [ "$total" -le "$pagesize" ]; then
  exit 0
fi

total_sub=$((width * 8))

thumb_sub=$((pagesize * total_sub / total))
[ "$thumb_sub" -lt 8 ] && thumb_sub=8
[ "$thumb_sub" -gt "$total_sub" ] && thumb_sub=$total_sub

scroll_max=$((total - pagesize))
if [ "$scroll_max" -le 0 ]; then
  from=0
else
  from=$(((scroll_max - pos) * (total_sub - thumb_sub) / scroll_max))
fi
[ "$from" -lt 0 ] && from=0
max_from=$((total_sub - thumb_sub))
[ "$from" -gt "$max_from" ] && from=$max_from
to=$((from + thumb_sub))

from_cell=$((from / 8))
to_cell=$(((to - 1) / 8))
from_offset=$((from % 8))
to_offset=$((to % 8))

blocks=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉' '█')

case "$mode" in
  prefix)
    for ((c = 0; c < from_cell; c++)); do printf ' '; done
    ;;
  thumb-start)
    if [ "$from_offset" -eq 0 ]; then
      # Full from cella → REVERSE-szelt space = teljes fehér cella
      printf ' '
    else
      # Partial: a thumb a cellán pixel from_offset..7 között foglal helyet
      # (jobb 8-from_offset pixel fehér). REVERSE blocks[from_offset] adja:
      # blocks[k] = bal k/8 fg → REVERSE = bal k/8 bg + jobb (8-k)/8 fg = jobb
      # (8-from_offset) pixel fehér ✓
      printf '%s' "${blocks[$from_offset]}"
    fi
    ;;
  suffix)
    if [ "$from_cell" -ne "$to_cell" ]; then
      # Middle full cellák
      for ((c = from_cell + 1; c < to_cell; c++)); do printf '█'; done
      # to cella
      if [ "$to_offset" -eq 0 ]; then
        printf '█'
      else
        printf '%s' "${blocks[$to_offset]}"
      fi
    fi
    # Trailing space-ek
    for ((c = to_cell + 1; c < width; c++)); do printf ' '; done
    ;;
esac
