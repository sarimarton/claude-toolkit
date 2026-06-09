#!/usr/bin/env bash
# Dictation pipeline — queue state machine library.
# Sourced by capture-target.sh, stop-record.sh, and dictation-worker.sh.
#
# The queue is a set of sibling directories on ONE filesystem (APFS under $HOME),
# so all state transitions are atomic rename(2) via `mv`:
#
#   $ROOT/active/<id>/       in-flight capture (recording), not yet enqueued
#   $ROOT/jobs/pending/<id>/ enqueued, awaiting the worker
#   $ROOT/jobs/processing/   claimed by the worker
#   $ROOT/jobs/done/         delivered
#   $ROOT/jobs/failed/       exceeded retry budget
#
# DICT_QUEUE_ROOT overrides the root (tests set it to a tmpdir). Default is the
# installed location alongside the existing topics/ IPC dir.
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

: "${DICT_QUEUE_ROOT:={{home}}/.config/claude-toolkit/dictation}"

_q_pending()    { printf '%s' "$DICT_QUEUE_ROOT/jobs/pending"; }
_q_processing() { printf '%s' "$DICT_QUEUE_ROOT/jobs/processing"; }
_q_done()       { printf '%s' "$DICT_QUEUE_ROOT/jobs/done"; }
_q_failed()     { printf '%s' "$DICT_QUEUE_ROOT/jobs/failed"; }
_q_active()     { printf '%s' "$DICT_QUEUE_ROOT/active"; }

# Ensure the queue skeleton exists (idempotent).
queue_init() {
  mkdir -p "$(_q_pending)" "$(_q_processing)" "$(_q_done)" "$(_q_failed)" "$(_q_active)"
}

# queue_enqueue <id>: atomically move active/<id> -> jobs/pending/<id>.
# Called only AFTER the WAV is finalized, so the worker never sees a partial file.
queue_enqueue() {
  local id="$1"
  [ -n "$id" ] || return 2
  mv "$(_q_active)/$id" "$(_q_pending)/$id"
}

# queue_claim: atomically claim the OLDEST pending job into processing.
# Prints the claimed id on stdout and returns 0; returns 1 (no output) if none.
# Atomicity: `mv` of a directory is atomic; if two workers race for the same job,
# exactly one `mv` succeeds and the loser retries the next candidate.
queue_claim() {
  local pend; pend="$(_q_pending)"
  local proc; proc="$(_q_processing)"
  local id
  # Oldest first (mtime ascending). `ls -1tr` lists oldest -> newest.
  for id in $(ls -1tr "$pend" 2>/dev/null); do
    if mv "$pend/$id" "$proc/$id" 2>/dev/null; then
      printf '%s' "$id"
      return 0
    fi
    # Lost the race for this id — try the next candidate.
  done
  return 1
}

# queue_finalize <id> <done|failed>: move processing/<id> -> jobs/<state>/<id>.
queue_finalize() {
  local id="$1" state="$2"
  [ -n "$id" ] || return 2
  case "$state" in
    done)   mv "$(_q_processing)/$id" "$(_q_done)/$id" ;;
    failed) mv "$(_q_processing)/$id" "$(_q_failed)/$id" ;;
    *) return 2 ;;
  esac
}

# queue_requeue_stale: on worker startup, move any orphaned processing jobs
# (left behind by a crash mid-transcribe) back to pending for a retry.
queue_requeue_stale() {
  local proc; proc="$(_q_processing)"
  local pend; pend="$(_q_pending)"
  local id
  for id in $(ls -1 "$proc" 2>/dev/null); do
    mv "$proc/$id" "$pend/$id" 2>/dev/null || true
  done
  return 0
}

# queue_bump_attempts <id>: increment the retry counter in processing/<id>/attempts,
# printing the new value. Used to detect poison jobs.
queue_bump_attempts() {
  local id="$1"
  local f="$(_q_processing)/$id/attempts"
  local n=0
  [ -f "$f" ] && n="$(cat "$f" 2>/dev/null || echo 0)"
  n=$((n + 1))
  printf '%s' "$n" > "$f"
  printf '%s' "$n"
}

# queue_over_budget <id> <max>: return 0 (true) if attempts >= max, else 1.
queue_over_budget() {
  local id="$1" max="$2"
  local f="$(_q_processing)/$id/attempts"
  local n=0
  [ -f "$f" ] && n="$(cat "$f" 2>/dev/null || echo 0)"
  [ "$n" -ge "$max" ]
}
