#!/usr/bin/env bash
# Post-install for the llm-cleanup-server module:
#  1. Deploy the vendored server JS to the runtime dir.
#  2. npm install --omit=dev (express only).
#  3. Resolve node/claude absolute paths into the LaunchAgent plist (launchd's
#     minimal PATH has neither nvm's node nor the `claude` zsh-function).
#  4. Bootstrap the LaunchAgent (bootout-wait-bootstrap, the toolkit/Finance pattern).
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

INSTALL_DIR="{{install_dir}}"
SCRIPTS_DIR="{{scripts_dir}}"
LAUNCH_AGENTS_DIR="{{launch_agents_dir}}"
RUNTIME="$INSTALL_DIR/dictation/llm-cleanup-server"
PLIST="$LAUNCH_AGENTS_DIR/com.sarim.llm-cleanup-server.plist"
LABEL="com.sarim.llm-cleanup-server"

echo "[llm-cleanup] deploying server to $RUNTIME"
mkdir -p "$RUNTIME"
# The vendored server is the source of truth in the toolkit repo.
SRC="{{repo_dir}}/src/modules/llm-cleanup-server/assets/server"
[ -d "$SRC" ] || { echo "[llm-cleanup] server source not found at $SRC" >&2; exit 1; }
cp -R "$SRC"/. "$RUNTIME"/

echo "[llm-cleanup] npm install (express only)"
( cd "$RUNTIME" && npm install --omit=dev --no-audit --no-fund >/tmp/llm-cleanup-npm.log 2>&1 ) \
  || { echo "[llm-cleanup] npm install failed (see /tmp/llm-cleanup-npm.log)" >&2; exit 1; }

echo "[llm-cleanup] resolving node/claude paths into plist"
NODE_BIN="$(command -v node || echo /usr/bin/env)"
# Prefer the stable launcher (fixed path; `claude` is a zsh function otherwise).
if [ -x "$HOME/.local/bin/claude" ]; then
  CLAUDE_BIN="$HOME/.local/bin/claude"
else
  CLAUDE_BIN="$(command -v claude || echo claude)"
fi
sed -e "s#__NODE_BIN__#$NODE_BIN#g" \
    -e "s#__CLAUDE_BIN__#$CLAUDE_BIN#g" \
    -e "s#__HOME__#$HOME#g" \
    "$PLIST" > "$PLIST.tmp" && mv "$PLIST.tmp" "$PLIST"

echo "[llm-cleanup] bootstrapping LaunchAgent"
domain="gui/$(id -u)"
launchctl bootout "$domain/$LABEL" 2>/dev/null || true
for _ in $(seq 1 50); do launchctl print "$domain/$LABEL" >/dev/null 2>&1 || break; sleep 0.1; done
launchctl bootstrap "$domain" "$PLIST" \
  || { echo "[llm-cleanup] bootstrap failed" >&2; exit 1; }

echo "[llm-cleanup] done — http://127.0.0.1:51733/health"
