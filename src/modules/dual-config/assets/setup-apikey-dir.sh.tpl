#!/usr/bin/env bash
# setup-apikey-dir.sh — Creates ~/.claude-apikey with symlinks to ~/.claude
# Run once after installing the dual-config module.
# Safe to re-run: skips existing files/symlinks.

set -euo pipefail

MAIN_DIR="$HOME/.claude"
APIKEY_DIR="$HOME/.claude-apikey"

if [[ ! -d "$MAIN_DIR" ]]; then
  echo "Error: $MAIN_DIR does not exist. Run claude once first." >&2
  exit 1
fi

mkdir -p "$APIKEY_DIR"

# Copy onboarding state (not symlinked — CLAUDE_CONFIG_DIR looks here)
if [[ -f "$HOME/.claude.json" && ! -f "$APIKEY_DIR/.claude.json" ]]; then
  cp "$HOME/.claude.json" "$APIKEY_DIR/.claude.json"
fi

# Symlink everything except settings.json and .claude.json
for item in "$MAIN_DIR"/*; do
  name=$(basename "$item")
  [[ "$name" == "settings.json" ]] && continue
  [[ "$name" == ".claude.json" ]] && continue
  [[ "$name" == "settings.json.tmp" ]] && continue
  [[ -e "$APIKEY_DIR/$name" || -L "$APIKEY_DIR/$name" ]] && continue
  ln -s "$item" "$APIKEY_DIR/$name"
done

# Create initial settings.json (will be overwritten on each claude() call)
if [[ ! -f "$APIKEY_DIR/settings.json" ]]; then
  {{jq}} 'del(.apiKeyHelper)' "$MAIN_DIR/settings.json" > "$APIKEY_DIR/settings.json" 2>/dev/null \
    || cp "$MAIN_DIR/settings.json" "$APIKEY_DIR/settings.json"
fi

echo "✓ $APIKEY_DIR created with symlinks to $MAIN_DIR"
echo ""
echo "Add to your .zshrc:"
echo "  source {{scripts_dir}}/claude-fn.sh"
