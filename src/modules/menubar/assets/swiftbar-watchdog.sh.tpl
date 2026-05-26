#!/bin/bash
# Second-line defense: ensures claude.10s.sh stays visible after SwiftBar starts.
# Triggered by LaunchAgent at login (RunAtLoad) and every 5 minutes (StartInterval).

PLUGIN="claude.10s.sh"
BUNDLE="com.ameba.SwiftBar"
COOLDOWN_FILE="/tmp/.swiftbar-claude-watchdog-ts"
COOLDOWN_SEC=270
LOG="/tmp/swiftbar-watchdog.log"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Prevent restart loops: no re-fix within 270s of last fix
if [ -f "$COOLDOWN_FILE" ]; then
    last=$(cat "$COOLDOWN_FILE")
    now=$(date +%s)
    (( now - last < COOLDOWN_SEC )) && exit 0
fi

# Wait for SwiftBar to be running (up to 2 minutes — needed at boot)
for _ in $(seq 1 24); do
    pgrep -x SwiftBar > /dev/null && break
    sleep 5
done
pgrep -x SwiftBar > /dev/null || exit 0

visible=$(defaults read "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" 2>/dev/null | tr -d ' ')
[ "$visible" = "0" ] || exit 0

echo "$(ts): claude.10s.sh hidden (VisibleCC=0), applying fix" >> "$LOG"
date +%s > "$COOLDOWN_FILE"

# killall -9 required — osascript quit leaves the PID alive (confirmed empirically)
killall -9 SwiftBar 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8; do pgrep -q SwiftBar || break; sleep 0.5; done

# Write BOTH: Preferred Position (prevents overflow) + VisibleCC (prevents hiding)
defaults write "$BUNDLE" "NSStatusItem Preferred Position $PLUGIN" -float 700
defaults write "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" -bool YES
open -a SwiftBar

echo "$(ts): SwiftBar restarted with fix applied" >> "$LOG"
