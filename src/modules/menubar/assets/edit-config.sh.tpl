#!/usr/bin/env bash
# edit-config.sh — Open the toolkit config in the default editor.
#
# All settings live in config.yaml under modules.* (read live at runtime, so edits
# take effect without a reinstall). This is toolkit-global, not module-specific.

CONFIG_FILE="{{config_file}}"

# Seed from the packaged default if the config doesn't exist yet.
if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  DEFAULT="{{repo_dir}}/config.default.yaml"
  if [ -f "$DEFAULT" ]; then cp "$DEFAULT" "$CONFIG_FILE"; else : > "$CONFIG_FILE"; fi
fi

# `open` honors the user's default app for .yaml; fall back to the default text editor.
open "$CONFIG_FILE" 2>/dev/null || open -t "$CONFIG_FILE"
