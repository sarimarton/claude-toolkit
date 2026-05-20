#!/usr/bin/env bash
# swiftbar-install.sh — Ensure SwiftBar.app is installed and pointed at the toolkit plugin dir.
#
# Runs as the menubar module's postInstall step. Idempotent: safe to re-run on every
# install/upgrade. Installs SwiftBar via Homebrew cask only when missing, always (re)asserts
# the PluginDirectory preference and refreshes the running app.

set -euo pipefail

PLUGIN_DIR="{{swiftbar_dir}}"
APP_PATHS=("/Applications/SwiftBar.app" "{{home}}/Applications/SwiftBar.app")

swiftbar_installed() {
  for p in "${APP_PATHS[@]}"; do
    [ -d "$p" ] && return 0
  done
  return 1
}

# 1. Install the app if absent.
if swiftbar_installed; then
  echo "SwiftBar already installed." >&2
else
  if ! command -v brew >/dev/null 2>&1; then
    echo "SwiftBar is not installed and Homebrew was not found." >&2
    echo "Install Homebrew (https://brew.sh) then re-run, or install SwiftBar manually:" >&2
    echo "  brew install --cask swiftbar" >&2
    exit 1
  fi
  echo "Installing SwiftBar via Homebrew..." >&2
  brew install --cask swiftbar >&2
fi

# 2. Point SwiftBar at the toolkit plugin directory (the same dir the plugin was deployed to).
mkdir -p "$PLUGIN_DIR"
defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR" >&2

# 3. Launch (or refresh) SwiftBar so the menu shows up immediately.
if pgrep -x SwiftBar >/dev/null 2>&1; then
  open "swiftbar://refreshallplugins" >/dev/null 2>&1 || true
else
  open -a SwiftBar >/dev/null 2>&1 || true
fi

echo "SwiftBar configured — plugins: $PLUGIN_DIR" >&2
