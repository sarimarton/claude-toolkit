#!/usr/bin/env bash
# Post-install for the dictation-pipeline module:
#  1. Create the queue directory skeleton.
#  2. Download the whisper ggml-large-v3 model if missing (idempotent, 2.9 GB).
#  3. Bootstrap the worker LaunchAgent (bootout-wait-bootstrap).
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

INSTALL_DIR="{{install_dir}}"
LAUNCH_AGENTS_DIR="{{launch_agents_dir}}"
QROOT="$INSTALL_DIR/dictation"
PLIST="$LAUNCH_AGENTS_DIR/com.sarim.dictation-worker.plist"
LABEL="com.sarim.dictation-worker"

echo "[dictation] creating queue dirs"
mkdir -p "$QROOT/jobs/pending" "$QROOT/jobs/processing" "$QROOT/jobs/done" \
         "$QROOT/jobs/failed" "$QROOT/active"

echo "[dictation] checking whisper model"
MODEL="$HOME/.cache/whisper-cpp/models/ggml-large-v3.bin"
if [ ! -s "$MODEL" ]; then
  echo "[dictation] downloading ggml-large-v3 (2.9 GB)…"
  mkdir -p "$(dirname "$MODEL")"
  curl -fL --retry 3 -o "$MODEL.partial" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin" \
    && mv "$MODEL.partial" "$MODEL" \
    || { echo "[dictation] WARN: model download failed; worker will fall back" >&2; rm -f "$MODEL.partial"; }
else
  echo "[dictation] model present, skipping download"
fi

echo "[dictation] bootstrapping worker LaunchAgent"
domain="gui/$(id -u)"
launchctl bootout "$domain/$LABEL" 2>/dev/null || true
for _ in $(seq 1 50); do launchctl print "$domain/$LABEL" >/dev/null 2>&1 || break; sleep 0.1; done
launchctl bootstrap "$domain" "$PLIST" \
  || { echo "[dictation] bootstrap failed" >&2; exit 1; }

echo "[dictation] done. Worker log: /tmp/dictation-worker.log"
echo "[dictation] NOTE: grant Microphone permission to Karabiner-Elements (and/or"
echo "[dictation]       your terminal) in System Settings → Privacy → Microphone."
