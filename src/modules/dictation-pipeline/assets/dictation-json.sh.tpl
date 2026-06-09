#!/usr/bin/env bash
# Dictation pipeline — safe JSON construction for meta.json and the /cleanup body.
#
# All untrusted text (tmux pane context, raw transcript) is passed via `jq --arg`,
# which performs full JSON string escaping. We NEVER interpolate text into a JSON
# string by hand, so quotes, backticks, $, newlines, backslashes, and multibyte
# UTF-8 (Hungarian accents) round-trip intact and no shell injection is possible.
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

JQ="{{jq}}"
command -v "$JQ" >/dev/null 2>&1 || JQ="jq"

# meta_json <id> <pane_id> <context> <send_enter:true|false> <lang>
# Emits the per-job meta.json. send_enter is a real JSON boolean (--argjson).
meta_json() {
  local id="$1" pane_id="$2" context="$3" send_enter="$4" lang="$5"
  # Normalize send_enter to a strict boolean literal for --argjson.
  case "$send_enter" in
    true|1|yes)  send_enter=true ;;
    *)           send_enter=false ;;
  esac
  "$JQ" -n \
    --arg id "$id" \
    --arg pane_id "$pane_id" \
    --arg context "$context" \
    --argjson send_enter "$send_enter" \
    --arg lang "$lang" \
    '{
      id: $id,
      pane_id: $pane_id,
      pane_context: $context,
      context_source: "tmux",
      send_enter: $send_enter,
      lang: $lang
    }'
}

# cleanup_body <text> <context>: emits {text, context} for POST /cleanup.
cleanup_body() {
  local text="$1" context="$2"
  "$JQ" -n \
    --arg text "$text" \
    --arg context "$context" \
    '{ text: $text, context: $context }'
}
