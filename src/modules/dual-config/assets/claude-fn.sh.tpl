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

# Prefer the TCC-stable launcher (stable-claude-bin module) so macOS file-access
# grants survive Claude's silent version updates; fall back to the version symlink.
CLAUDE_BIN={{scripts_dir}}/claude-stable
[[ -x "$CLAUDE_BIN" ]] || CLAUDE_BIN={{claude}}
CLAUDE_APIKEY_DIR="$HOME/.claude-apikey"

claude() {
  local main_settings="$HOME/.claude/settings.json"

  [[ ! -f "$main_settings" ]] && echo "{}" > "$main_settings"

  # Personal/policy flags injected by the consumer's .zshrc via CLAUDE_EXTRA_ARGS
  # (toolkit stays neutral; policy lives in the consumer config). Word-split so
  # multiple flags pass through; prepend before "$@" so explicit CLI args win.
  local extra_args=()
  if [[ -n "$CLAUDE_EXTRA_ARGS" ]]; then
    if [[ -n "$ZSH_VERSION" ]]; then
      extra_args=(${=CLAUDE_EXTRA_ARGS})
    else
      extra_args=($CLAUDE_EXTRA_ARGS)
    fi
  fi

  if [[ -d "$CLAUDE_APIKEY_DIR" && -n "$ANTHROPIC_API_KEY" ]]; then
    # Sync settings + inject apiKeyHelper for API key mode
    {{jq}} --arg key "$ANTHROPIC_API_KEY" \
      '. + {apiKeyHelper: ("echo " + $key)}' \
      "$main_settings" > "$CLAUDE_APIKEY_DIR/settings.json"
    CLAUDE_CONFIG_DIR="$CLAUDE_APIKEY_DIR" "$CLAUDE_BIN" "${extra_args[@]}" "$@"
  else
    # Default: OAuth mode via ~/.claude
    "$CLAUDE_BIN" "${extra_args[@]}" "$@"
  fi
}
alias c='claude'
