#!/usr/bin/env bash
# auto-dev-global-config.sh — Open the toolkit config in the default editor.
#
# All settings now live in config.yaml under modules.* (auto-dev under
# modules.autoDev: maxIssuesPerRun, bailoutPct, repos.<owner/repo>.autonomy).
# Editing the file takes effect on the next run — every consumer reads it live.
# No gum, no separate global.json.

CONFIG_FILE="{{config_file}}"

# Seed from the packaged default if the config doesn't exist yet.
if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  DEFAULT="{{repo_dir}}/config.default.yaml"
  if [ -f "$DEFAULT" ]; then cp "$DEFAULT" "$CONFIG_FILE"; else : > "$CONFIG_FILE"; fi
fi

# `open` honors the user's default app for .yaml; fall back to the default text editor.
open "$CONFIG_FILE" 2>/dev/null || open -t "$CONFIG_FILE"
