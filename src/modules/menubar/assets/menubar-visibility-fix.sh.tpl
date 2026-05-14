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
# Run by a LaunchAgent at user login (RunAtLoad) and every StartInterval
# seconds. Idempotent. Silent fast path when flag=1 AND SwiftBar running.
# Otherwise: writes flag, optionally restarts SwiftBar, always ensures
# SwiftBar is open via `open -a` (login-race-proof — login items may not
# have started SwiftBar yet when this script first runs).

PLUGIN="claude.10s.sh"
KEY="NSStatusItem VisibleCC ${PLUGIN}"
DOMAIN="com.ameba.SwiftBar"
LOG="/tmp/claude-toolkit-menubar-visibility.log"

log() {
  /bin/echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

current="$(/usr/bin/defaults read "$DOMAIN" "$KEY" 2>/dev/null || /bin/echo "")"
swiftbar_running=false
if /usr/bin/pgrep -q SwiftBar; then
  swiftbar_running=true
fi

# Silent fast path: nothing to do, no log noise.
if [ "$current" = "1" ] && [ "$swiftbar_running" = "true" ]; then
  exit 0
fi

log "begin: current=${current:-<unset>} swiftbar_running=$swiftbar_running"

if [ "$current" != "1" ]; then
  /usr/bin/defaults write "$DOMAIN" "$KEY" -bool YES
  log "wrote VisibleCC=1 (was: ${current:-<unset>})"
fi

if [ "$swiftbar_running" = "true" ]; then
  /usr/bin/killall SwiftBar 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/pgrep -q SwiftBar || break
    sleep 0.5
  done
  log "killed SwiftBar to reload defaults"
fi

/usr/bin/open -a SwiftBar
log "opened SwiftBar"
