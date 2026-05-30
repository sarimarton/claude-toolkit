#!/usr/bin/env bash
# swiftbar-install.sh — Ensure SwiftBar.app is installed and pointed at the toolkit plugin dir.
#
# Runs as the menubar module's postInstall step. Idempotent: safe to re-run on every
# install/upgrade. Installs SwiftBar via Homebrew cask only when missing, always (re)asserts
# the PluginDirectory preference and refreshes the running app.

set -euo pipefail

DEPLOY_DIR="{{swiftbar_dir}}"
PLUGIN_DIR="{{swiftbar_plugin_dir}}"
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

# 2. Make our plugin visible by living in the SHARED user SwiftBar dir, never a
#    toolkit-private one. SwiftBar reads exactly one PluginDirectory, so we make
#    room for everyone: we point it at the conventional ~/.config/swiftbar
#    (PLUGIN_DIR) — even when we're the only plugin there — so the user can drop
#    their own plugins in later with zero conflict, and we deploy ours into it as
#    a symlink to the internal deploy dir.
#
# Two things we deliberately DON'T do (both were the old eviction bug):
#   - never set SwiftBar to our internal deploy dir ($DEPLOY_DIR)
#   - never override a plugin dir the user has already chosen for themselves
DEPLOY_DIR_REAL=$(cd "$DEPLOY_DIR" 2>/dev/null && pwd -P || echo "$DEPLOY_DIR")
current_dir=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)
current_real=$([ -n "$current_dir" ] && cd "$current_dir" 2>/dev/null && pwd -P || echo "$current_dir")

# Respect a user-chosen dir; discard a pref that points at our internal deploy dir
# (self-inflicted bad state from older versions) → fall back to ~/.config/swiftbar.
if [ -n "$current_dir" ] && [ "$current_real" != "$DEPLOY_DIR_REAL" ]; then
  ACTIVE_DIR="$current_dir"
else
  ACTIVE_DIR="$PLUGIN_DIR"
fi
mkdir -p "$ACTIVE_DIR"

# Only touch the preference when it actually needs to change — never clobber a good value.
if [ "$current_dir" != "$ACTIVE_DIR" ]; then
  defaults write com.ameba.SwiftBar PluginDirectory "$ACTIVE_DIR" >&2
  echo "SwiftBar plugin dir set to: $ACTIVE_DIR" >&2
fi

# Deploy each of our .sh plugins into the active dir as a REAL FILE copy — never a
# symlink. SwiftBar does not reliably load a symlinked plugin whose target lives
# outside the plugin dir: the script still runs on schedule (its output cache keeps
# updating), but the menu-bar item never appears. The identical file copied in
# place shows up immediately. This loop only iterates OUR deployed plugins, so it
# never touches the user's own hand-managed plugins (vpn, wiredleak, …) in the dir.
for deployed in "$DEPLOY_DIR"/*.sh; do
  [ -f "$deployed" ] || continue
  dest="$ACTIVE_DIR/$(basename "$deployed")"
  rm -f "$dest"            # clear any old symlink or stale copy
  cp "$deployed" "$dest"
  chmod +x "$dest"
done

# 3. Launch (or refresh) SwiftBar so the menu shows up immediately.
if pgrep -x SwiftBar >/dev/null 2>&1; then
  open "swiftbar://refreshallplugins" >/dev/null 2>&1 || true
else
  open -a SwiftBar >/dev/null 2>&1 || true
fi

# 4. Install the watchdog LaunchAgent (keeps claude.10s.sh visible after reboot).
WATCHDOG_PLIST="{{launch_agents_dir}}/com.sarim.swiftbar-claude-watchdog.plist"
if [ -f "$WATCHDOG_PLIST" ]; then
  launchctl unload "$WATCHDOG_PLIST" 2>/dev/null || true
  launchctl load "$WATCHDOG_PLIST"
  echo "SwiftBar watchdog LaunchAgent loaded." >&2
fi

echo "SwiftBar configured — plugins: $ACTIVE_DIR" >&2
