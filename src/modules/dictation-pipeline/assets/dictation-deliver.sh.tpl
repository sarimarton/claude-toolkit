#!/usr/bin/env bash
# Dictation pipeline — deliver cleaned text into the TARGET tmux pane.
#
# Correctness is the whole point of this script:
#  * The text is inserted LITERALLY with `send-keys -t <pane> -l -- "$text"`:
#      -l  = literal (tmux does NOT interpret key names like "Enter"/"C-c");
#      --  = end of option parsing, so text starting with '-' is never a flag;
#      "$text" is ONE argv element, so no word-splitting / no shell expansion.
#  * Enter (submit) is a SEPARATE call WITHOUT -l, so it's the Enter KEY — not the
#    literal word "Enter". Kept separate so the literal text never contains a
#    trailing newline that would submit a multi-line paragraph prematurely.
#  * Target-bound: we address the pane by its id (%NN) captured at dictation time,
#    so focus changes never misroute (the core "wrong tab" fix).
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

TMUX_BIN="{{tmux}}"
JQ="{{jq}}"
command -v "$TMUX_BIN" >/dev/null 2>&1 || TMUX_BIN="tmux"
command -v "$JQ" >/dev/null 2>&1 || JQ="jq"

job_dir="${1:?usage: dictation-deliver.sh <processing-job-dir>}"
meta="$job_dir/meta.json"
cleaned="$job_dir/cleaned.txt"

[ -f "$meta" ]    || { echo "deliver: missing meta.json in $job_dir" >&2; exit 1; }
[ -f "$cleaned" ] || { echo "deliver: missing cleaned.txt in $job_dir" >&2; exit 1; }

pane_id="$("$JQ" -r '.pane_id'   "$meta")"
send_enter="$("$JQ" -r '.send_enter' "$meta")"
text="$(cat "$cleaned")"

[ -n "$pane_id" ] && [ "$pane_id" != "null" ] || { echo "deliver: no pane_id" >&2; exit 1; }

# Guard: the target pane must still exist; never insert into a recycled pane id.
if ! "$TMUX_BIN" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane_id"; then
  echo "deliver: target pane $pane_id is gone; dropping job $job_dir" >&2
  exit 0
fi

# 1) Literal text — single argv element, no interpretation.
"$TMUX_BIN" send-keys -t "$pane_id" -l -- "$text"

# 2) Optional submit — Enter as a key, separate call, NOT literal.
if [ "$send_enter" = "true" ]; then
  "$TMUX_BIN" send-keys -t "$pane_id" Enter
fi
