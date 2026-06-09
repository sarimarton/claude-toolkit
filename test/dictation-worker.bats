#!/usr/bin/env bats
# Worker-loop integration: with stubbed transcribe/cleanup/deliver, a job placed in
# pending/ must flow pending -> processing -> done with cleaned.txt produced.
#
# Externals are injected via the worker's DICT_*_BIN env hooks (NOT via PATH order:
# the worker prepends /opt/homebrew/bin for launchd, which would shadow PATH shims).

setup() {
  TESTDIR="$(mktemp -d)"
  QROOT="$TESTDIR/dictation"
  mkdir -p "$QROOT/jobs/pending" "$QROOT/jobs/processing" "$QROOT/jobs/done" \
           "$QROOT/jobs/failed" "$QROOT/active"

  BIN="$TESTDIR/bin"; mkdir -p "$BIN"
  SCRIPTS="$TESTDIR/scripts"; mkdir -p "$SCRIPTS"
  MODDIR="$BATS_TEST_DIRNAME/../src/modules/dictation-pipeline/assets"
  JQ="$(command -v jq)"

  # Stub externals.
  # whisper-server: exit 1 so the worker falls back to the CLI stub.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/whisper-server-stub"
  # whisper-cli: fixed raw transcript.
  printf '#!/usr/bin/env bash\necho "raw transcript from stub"\n' > "$BIN/whisper-cli-stub"
  # curl: health -> fail (forces cli fallback); cleanup -> canned JSON.
  cat > "$BIN/curl-stub" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *"/cleanup") echo '{"text":"CLEANED transcript"}'; exit 0 ;;
  esac
done
# health check on the whisper port: fail so the worker uses the cli fallback.
exit 7
EOF
  # tmux: pane exists; send-keys ok.
  printf '#!/usr/bin/env bash\ncase "$1" in list-panes) echo "%%1"; exit 0 ;; send-keys) exit 0 ;; esac\nexit 0\n' > "$BIN/tmux"
  chmod +x "$BIN"/*

  for f in dictation-queue.sh dictation-json.sh dictation-deliver.sh dictation-worker.sh; do
    sed -e "s#{{tmux}}#$BIN/tmux#g" -e "s#{{jq}}#$JQ#g" -e "s#{{home}}#$TESTDIR#g" \
        "$MODDIR/$f.tpl" > "$SCRIPTS/$f"
    chmod +x "$SCRIPTS/$f"
  done
}
teardown() {
  [ -n "${WPID:-}" ] && kill "$WPID" 2>/dev/null || true
  rm -rf "$TESTDIR"
}

mk_pending_job() {
  local id="$1"
  local d="$QROOT/jobs/pending/$id"
  mkdir -p "$d"
  "$(command -v jq)" -n --arg id "$id" \
    '{id:$id,pane_id:"%1",pane_context:"ctx",send_enter:true,lang:"auto"}' > "$d/meta.json"
  printf 'WAVDATA' > "$d/audio.wav"
}

@test "worker flows a pending job to done with cleaned text (stubbed externals)" {
  mk_pending_job "jobZ"
  printf 'X' > "$TESTDIR/fake-model.bin"

  DICT_QUEUE_ROOT="$QROOT" \
  DICT_WHISPER_MODEL="$TESTDIR/fake-model.bin" \
  DICT_WHISPER_SERVER_BIN="$BIN/whisper-server-stub" \
  DICT_WHISPER_CLI_BIN="$BIN/whisper-cli-stub" \
  DICT_CURL_BIN="$BIN/curl-stub" \
    bash "$SCRIPTS/dictation-worker.sh" &
  WPID=$!

  ok=""
  for _ in $(seq 1 80); do
    if [ -d "$QROOT/jobs/done/jobZ" ]; then ok=1; break; fi
    sleep 0.1
  done
  kill "$WPID" 2>/dev/null || true

  [ -n "$ok" ]
  [ -f "$QROOT/jobs/done/jobZ/cleaned.txt" ]
  [ "$(cat "$QROOT/jobs/done/jobZ/cleaned.txt")" = "CLEANED transcript" ]
  [ "$(cat "$QROOT/jobs/done/jobZ/transcript.txt")" = "raw transcript from stub" ]
}

@test "worker requeues then fails a job whose transcript stays empty" {
  mk_pending_job "poison"
  printf 'X' > "$TESTDIR/fake-model.bin"
  # whisper-cli stub that emits NOTHING -> empty transcript every attempt.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/whisper-empty"
  chmod +x "$BIN/whisper-empty"

  DICT_QUEUE_ROOT="$QROOT" \
  DICT_WHISPER_MODEL="$TESTDIR/fake-model.bin" \
  DICT_WHISPER_SERVER_BIN="$BIN/whisper-server-stub" \
  DICT_WHISPER_CLI_BIN="$BIN/whisper-empty" \
  DICT_CURL_BIN="$BIN/curl-stub" \
    bash "$SCRIPTS/dictation-worker.sh" &
  WPID=$!

  ok=""
  for _ in $(seq 1 80); do
    if [ -d "$QROOT/jobs/failed/poison" ]; then ok=1; break; fi
    sleep 0.1
  done
  kill "$WPID" 2>/dev/null || true

  [ -n "$ok" ]   # exceeded retry budget -> failed/
}
