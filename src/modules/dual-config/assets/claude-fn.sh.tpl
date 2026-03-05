#!/usr/bin/env bash
# claude-fn.sh — Dual-config claude() shell function
# Source this from your .zshrc:  source {{scripts_dir}}/claude-fn.sh
#
# Architecture:
#   ~/.claude/         → OAuth (default, subscription mode)
#   ~/.claude-apikey/  → API key mode (only when ANTHROPIC_API_KEY is set)
#
# The function syncs settings.json from ~/.claude → ~/.claude-apikey
# (injecting apiKeyHelper) on every invocation, so both dirs stay in sync.

CLAUDE_BIN={{claude}}
CLAUDE_APIKEY_DIR="$HOME/.claude-apikey"

claude() {
  local main_settings="$HOME/.claude/settings.json"

  [[ ! -f "$main_settings" ]] && echo "{}" > "$main_settings"

  if [[ -d "$CLAUDE_APIKEY_DIR" && -n "$ANTHROPIC_API_KEY" ]]; then
    # Sync settings + inject apiKeyHelper for API key mode
    {{jq}} --arg key "$ANTHROPIC_API_KEY" \
      '. + {apiKeyHelper: ("echo " + $key)}' \
      "$main_settings" > "$CLAUDE_APIKEY_DIR/settings.json"
    CLAUDE_CONFIG_DIR="$CLAUDE_APIKEY_DIR" "$CLAUDE_BIN" "$@"
  else
    # Default: OAuth mode via ~/.claude
    "$CLAUDE_BIN" "$@"
  fi
}
alias c='claude'
