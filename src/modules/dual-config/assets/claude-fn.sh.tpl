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

CLAUDE_APIKEY_DIR="$HOME/.claude-apikey"

claude() {
  local main_settings="$HOME/.claude/settings.json"

  # Resolve the TCC-stable launcher INSIDE the function on every call — never via
  # a top-level $CLAUDE_BIN global. Claude freezes this function into a shell
  # snapshot, but a top-level assignment is fragile across snapshotting: a stale
  # or non-carried-over global would make us fall through to the versioned path
  # (~/.local/bin/claude), which pins the background daemon to versions/<X> and
  # re-triggers the TCC folder-prompt flood on every silent update. Resolving
  # here keeps the binary path snapshot-independent. Prefer the stable launcher;
  # fall back to the version symlink only if it is genuinely absent.
  local claude_bin={{scripts_dir}}/claude-stable
  [[ -x "$claude_bin" ]] || claude_bin={{claude}}

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
    CLAUDE_CONFIG_DIR="$CLAUDE_APIKEY_DIR" "$claude_bin" "${extra_args[@]}" "$@"
  else
    # Default: OAuth mode via ~/.claude
    "$claude_bin" "${extra_args[@]}" "$@"
  fi
}
alias c='claude'
