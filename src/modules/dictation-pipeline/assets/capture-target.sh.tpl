#!/usr/bin/env bash
# Dictation pipeline — capture-target (key-DOWN of the push-to-talk chord).
#
# Snapshots the romantically-perishable state NOW (which pane is the target, what
# is on its screen) and starts recording, then returns INSTANTLY so the shortcut
# frees and the user can move to the next tab and dictate again. The slow pipeline
# (transcribe/cleanup/deliver) never references live UI state afterwards.
#
# Prints the new job id on stdout (Karabiner redirects it to a marker file that
# stop-record.sh reads on key-up).
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SELF_DIR/dictation-queue.sh"
# shellcheck source=/dev/null
source "$SELF_DIR/dictation-json.sh"

TMUX_BIN="{{tmux}}"; command -v "$TMUX_BIN" >/dev/null 2>&1 || TMUX_BIN="tmux"

# send_enter default: submit after delivery. Can be overridden via arg ($1=noenter).
SEND_ENTER="true"
[ "${1:-}" = "noenter" ] && SEND_ENTER="false"

# Mic device: resolve BY NAME (avfoundation indices aren't hot-plug stable).
MIC_NAME="${DICT_MIC_NAME:-MacBook Air Microphone}"
mic_index() {
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
    | awk -F'[][]' -v n="$MIC_NAME" '$0 ~ n && /\[[0-9]+\]/ {print $2; exit}'
}

queue_init

# Job id: monotonic-ish, sortable, unique per capture.
id="$(date +%s%N)-$$"
job="$(_q_active)/$id"
mkdir -p "$job"

# Target pane: the active pane of the most-recently-active client (the focused
# iTerm pane at key-down). Snapshot it NOW.
pane_id="$("$TMUX_BIN" display-message -p '#{pane_id}' 2>/dev/null || echo '')"
if [ -z "$pane_id" ]; then
  echo "capture: no tmux pane in focus; aborting job $id" >&2
  rm -rf "$job"
  exit 1
fi

# Context: last ~200 lines incl. scrollback (clean plaintext, no escape codes),
# trimmed to a sane size for the cleanup prompt.
ctx="$("$TMUX_BIN" capture-pane -p -t "$pane_id" -S -200 2>/dev/null | tail -c 4096 || true)"

meta_json "$id" "$pane_id" "$ctx" "$SEND_ENTER" "auto" > "$job/meta.json"

# Start recording (16 kHz mono — whisper's native rate, no resampling later).
dev="$(mic_index)"; dev="${dev:-1}"
ffmpeg -nostdin -loglevel error -f avfoundation -i ":$dev" -ar 16000 -ac 1 "$job/audio.wav" -y \
  >>"$DICT_QUEUE_ROOT/worker.log" 2>&1 &
echo $! > "$job/ffmpeg.pid"

printf '%s' "$id"
