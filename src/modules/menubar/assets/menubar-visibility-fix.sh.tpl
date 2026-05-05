#!/bin/bash
# menubar-visibility-fix.sh — ensures the claude.10s.sh SwiftBar plugin is
# visible in the macOS menu bar.
#
# Why this exists: macOS persists each NSStatusItem's visibility flag in
# com.ameba.SwiftBar's defaults. When the user accidentally Cmd+drags the
# icon out of the menu bar (or it gets hidden via Control Center on
# Sonoma+), the flag flips to 0 and survives reboots. The plugin script
# still runs, but the icon never reappears.
#
# Run by the LaunchAgent at user login (RunAtLoad). Idempotent: only acts
# when the flag is missing or 0; restarts SwiftBar only if it is already
# running so the new value is picked up.

set -e

PLUGIN="claude.10s.sh"
KEY="NSStatusItem VisibleCC ${PLUGIN}"
DOMAIN="com.ameba.SwiftBar"

current="$(/usr/bin/defaults read "$DOMAIN" "$KEY" 2>/dev/null || echo "")"

if [ "$current" = "1" ]; then
  exit 0
fi

/usr/bin/defaults write "$DOMAIN" "$KEY" -bool YES

if /usr/bin/pgrep -q SwiftBar; then
  /usr/bin/killall SwiftBar 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    /usr/bin/pgrep -q SwiftBar || break
    sleep 0.5
  done
  /usr/bin/open -a SwiftBar
fi
