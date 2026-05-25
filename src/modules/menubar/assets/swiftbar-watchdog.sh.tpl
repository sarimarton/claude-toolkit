#!/bin/bash
# Watchdog: ensures the claude.10s.sh SwiftBar plugin stays visible.
# Run by LaunchAgent at login and every 5 minutes.
# Fixes the NSStatusItem VisibleCC = 0 bug that hides the item after reboot.

PLUGIN="claude.10s.sh"
PREF_KEY="NSStatusItem VisibleCC $PLUGIN"
SWIFTBAR_BUNDLE="com.ameba.SwiftBar"

# Wait for SwiftBar to be running (up to 2 minutes)
for i in $(seq 1 24); do
    pgrep -x SwiftBar > /dev/null && break
    sleep 5
done

visible=$(defaults read "$SWIFTBAR_BUNDLE" "$PREF_KEY" 2>/dev/null)
if [ "$visible" = "0" ]; then
    defaults write "$SWIFTBAR_BUNDLE" "$PREF_KEY" -bool true
    osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
    sleep 2
    open -a SwiftBar
fi
