#!/usr/bin/env bash
# auto-dev-config.sh — Open the toolkit config to set a repo's auto-dev autonomy.
#
# Per-repo autonomy now lives in config.yaml under
#   modules.autoDev.repos.<owner/repo>.autonomy   (high | low)
# high: opens issues + PRs + pushes commits autonomously
# low:  opens issues + comments only (no PRs, no pushes)
#
# This ensures the repo's entry exists (default high), then opens the config in the
# default editor. No gum, no GitHub repo variable — the workflow reads config.yaml.

REPO="$1"
[ -z "$REPO" ] && exit 0

YQ={{yq}}
CONFIG_FILE="{{config_file}}"

if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  DEFAULT="{{repo_dir}}/config.default.yaml"
  if [ -f "$DEFAULT" ]; then cp "$DEFAULT" "$CONFIG_FILE"; else : > "$CONFIG_FILE"; fi
fi

# Seed this repo's autonomy entry (default high) if absent, so there's a line to edit.
GH_REPO="$REPO" "$YQ" -i \
  '.modules.autoDev.repos[strenv(GH_REPO)].autonomy = (.modules.autoDev.repos[strenv(GH_REPO)].autonomy // "high")' \
  "$CONFIG_FILE" 2>/dev/null || true

# `open` honors the user's default app for .yaml; fall back to the default text editor.
open "$CONFIG_FILE" 2>/dev/null || open -t "$CONFIG_FILE"
