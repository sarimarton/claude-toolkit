#!/usr/bin/env bash
# Dictation pipeline — stop-record (key-UP of the push-to-talk chord).
#
# Finalizes the WAV (SIGINT to ffmpeg so it flushes a valid header/trailer — NEVER
# SIGKILL, which truncates) and atomically enqueues the job. The shortcut is now
# free; the user has already moved on.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SELF_DIR/dictation-queue.sh"

id="${1:-}"
[ -n "$id" ] || { echo "stop-record: no job id" >&2; exit 1; }

job="$(_q_active)/$id"
[ -d "$job" ] || { echo "stop-record: no active job $id" >&2; exit 1; }

# Stop ffmpeg gracefully and WAIT for it to finalize the WAV.
if [ -f "$job/ffmpeg.pid" ]; then
  pid="$(cat "$job/ffmpeg.pid")"
  kill -INT "$pid" 2>/dev/null || true
  # Bounded wait (<=2s) for the process to exit and flush the trailer.
  for _ in $(seq 1 20); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null || true
fi

# Drop empty/half-second mis-taps (no real audio) rather than enqueue garbage.
if [ ! -s "$job/audio.wav" ]; then
  echo "stop-record: empty recording for $id; discarding" >&2
  rm -rf "$job"
  exit 0
fi

# Atomic enqueue: active/<id> -> jobs/pending/<id>.
queue_enqueue "$id"
