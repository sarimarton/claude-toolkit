#!/usr/bin/env bash
# install-ext.sh — Build and install/uninstall the VS Code Terminal Topic extension
#
# Usage:
#   install-ext.sh install    Build + install extension into VS Code
#   install-ext.sh uninstall  Remove extension from VS Code

set -euo pipefail

ACTION="${1:-install}"
TOOLKIT_DIR="{{home}}/.local/share/claude-toolkit"
EXT_DIR="$TOOLKIT_DIR/src/modules/vscode-terminal-topic/extension"
VSCODE_EXT_ID="sarim.vscode-terminal-topic"
VSCODE_EXT_DIR="{{home}}/.vscode/extensions/${VSCODE_EXT_ID}-0.1.0"

case "$ACTION" in
  install)
    if [ ! -d "$EXT_DIR" ]; then
      echo "Extension source not found at $EXT_DIR" >&2
      exit 1
    fi

    # Build
    (cd "$EXT_DIR" && npm ci --ignore-scripts && npm run compile) >&2

    # Install via vsce if available, otherwise direct copy
    if command -v vsce >/dev/null 2>&1; then
      (cd "$EXT_DIR" && vsce package -o "$EXT_DIR/vscode-terminal-topic.vsix" && code --install-extension "$EXT_DIR/vscode-terminal-topic.vsix" --force) >&2
    else
      mkdir -p "$VSCODE_EXT_DIR/out"
      cp "$EXT_DIR/package.json" "$VSCODE_EXT_DIR/"
      cp "$EXT_DIR/out/extension.js" "$VSCODE_EXT_DIR/out/"
      cp "$EXT_DIR/out/extension.js.map" "$VSCODE_EXT_DIR/out/" 2>/dev/null || true
    fi
    ;;

  uninstall)
    if command -v code >/dev/null 2>&1; then
      code --uninstall-extension "$VSCODE_EXT_ID" 2>/dev/null || true
    fi
    rm -rf "$VSCODE_EXT_DIR" 2>/dev/null || true
    ;;

  *)
    echo "Usage: $0 {install|uninstall}" >&2
    exit 1
    ;;
esac
