#!/usr/bin/env bash
# Dictation pipeline — resident worker daemon (launchd KeepAlive).
#
# Single long-lived process that:
#  * starts a resident whisper-server ONCE (holds the 2.9 GB model in-process, so
#    each job pays only encode, not the ~2.6s model reload — measured ~5.5s vs
#    ~8.5s for per-job whisper-cli spawns);
#  * polls the queue (0.25s; fswatch isn't installed and polling a tiny dir is
#    negligible) and runs each job: transcribe -> cleanup -> deliver;
#  * recovers crashed jobs on startup and bounds retries (poison-job guard).
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SELF_DIR/dictation-queue.sh"
# shellcheck source=/dev/null
source "$SELF_DIR/dictation-json.sh"

JQ="{{jq}}"; command -v "$JQ" >/dev/null 2>&1 || JQ="jq"
MODEL="${DICT_WHISPER_MODEL:-{{home}}/.cache/whisper-cpp/models/ggml-large-v3.bin}"
WHISPER_PORT="${DICT_WHISPER_PORT:-51734}"
CLEANUP_URL="${DICT_CLEANUP_URL:-http://127.0.0.1:51733/cleanup}"
# External commands are env-overridable so tests can inject stubs WITHOUT relying
# on PATH order (the PATH line above intentionally prepends /opt/homebrew/bin for
# launchd, which would otherwise shadow PATH-based test shims).
WHISPER_SERVER_BIN="${DICT_WHISPER_SERVER_BIN:-whisper-server}"
WHISPER_CLI_BIN="${DICT_WHISPER_CLI_BIN:-whisper-cli}"
CURL_BIN="${DICT_CURL_BIN:-curl}"
LOG="$DICT_QUEUE_ROOT/worker.log"
LOCK="$DICT_QUEUE_ROOT/worker.lock"
MAX_ATTEMPTS=3

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }

queue_init

# Singleton: only one worker even if launchd double-bootstraps. macOS has no
# flock(1), so we use an atomic mkdir lock + a PID file. If the lock dir exists
# but its PID is dead (stale after a crash), we reclaim it.
LOCKDIR="$LOCK.d"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  oldpid="$(cat "$LOCKDIR/pid" 2>/dev/null || echo '')"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    log "another worker (pid $oldpid) holds the lock; exiting"
    exit 0
  fi
  log "reclaiming stale lock (dead pid ${oldpid:-none})"
fi
echo "$$" > "$LOCKDIR/pid"

# --- resident whisper-server -------------------------------------------------
WS_PID=""
start_whisper_server() {
  if [ ! -s "$MODEL" ]; then
    log "WARN: whisper model missing ($MODEL); falling back to per-job whisper-cli"
    return 1
  fi
  "$WHISPER_SERVER_BIN" -m "$MODEL" --host 127.0.0.1 --port "$WHISPER_PORT" -l auto \
    >> "$LOG" 2>&1 &
  WS_PID=$!
  # Health-check: wait for the inference port to answer.
  for _ in $(seq 1 60); do
    "$CURL_BIN" -s -o /dev/null "http://127.0.0.1:$WHISPER_PORT/" 2>/dev/null && { log "whisper-server up (pid $WS_PID)"; return 0; }
    kill -0 "$WS_PID" 2>/dev/null || { log "whisper-server died on startup"; WS_PID=""; return 1; }
    sleep 0.5
  done
  log "whisper-server health-check timed out"; return 1
}

cleanup_exit() {
  [ -n "$WS_PID" ] && kill "$WS_PID" 2>/dev/null || true
  # Only release the lock if it's still ours.
  [ "$(cat "$LOCKDIR/pid" 2>/dev/null || echo)" = "$$" ] && rm -rf "$LOCKDIR" 2>/dev/null || true
}
trap cleanup_exit EXIT

# transcribe <wav> -> text on stdout. Prefer the resident server; fall back to CLI.
transcribe() {
  local wav="$1"
  if [ -n "$WS_PID" ] && kill -0 "$WS_PID" 2>/dev/null; then
    "$CURL_BIN" -s --max-time 60 "http://127.0.0.1:$WHISPER_PORT/inference" \
      -F file=@"$wav" -F language=auto -F response_format=text 2>/dev/null
  else
    "$WHISPER_CLI_BIN" -m "$MODEL" -f "$wav" -l auto -nt 2>/dev/null
  fi
}

# --- main loop ---------------------------------------------------------------
queue_requeue_stale
start_whisper_server || log "proceeding without resident whisper-server"
log "worker started (poll 0.25s, cleanup=$CLEANUP_URL)"

while true; do
  id="$(queue_claim || true)"
  if [ -z "$id" ]; then
    sleep 0.25
    continue
  fi

  d="$(_q_processing)/$id"
  attempts="$(queue_bump_attempts "$id")"
  t0="$(date +%s)"

  # 1. transcribe
  raw="$(transcribe "$d/audio.wav" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf '%s' "$raw" > "$d/transcript.txt"

  if [ -z "$raw" ]; then
    if queue_over_budget "$id" "$MAX_ATTEMPTS"; then
      log "job $id: empty transcript after $attempts attempts -> failed"
      queue_finalize "$id" "failed"
    else
      log "job $id: empty transcript (attempt $attempts) -> requeue"
      mv "$d" "$(_q_pending)/$id" 2>/dev/null || true
    fi
    continue
  fi

  # 2. cleanup (always on, fail-open to raw)
  ctx="$("$JQ" -r '.pane_context // ""' "$d/meta.json")"
  body="$(cleanup_body "$raw" "$ctx")"
  cleaned="$("$CURL_BIN" -sS --max-time 30 "$CLEANUP_URL" \
    -H 'content-type: application/json' --data "$body" 2>/dev/null \
    | "$JQ" -r '.text // empty' 2>/dev/null || true)"
  [ -z "$cleaned" ] && { cleaned="$raw"; log "job $id: cleanup unavailable, delivering raw"; }
  printf '%s' "$cleaned" > "$d/cleaned.txt"

  # 3. deliver (target-bound, never wrong tab)
  if "$SELF_DIR/dictation-deliver.sh" "$d" >> "$LOG" 2>&1; then
    queue_finalize "$id" "done"
    log "job $id: delivered in $(( $(date +%s) - t0 ))s (attempt $attempts)"
  else
    if queue_over_budget "$id" "$MAX_ATTEMPTS"; then
      log "job $id: deliver failed after $attempts -> failed"
      queue_finalize "$id" "failed"
    else
      log "job $id: deliver failed (attempt $attempts) -> requeue"
      mv "$d" "$(_q_pending)/$id" 2>/dev/null || true
    fi
  fi
done
