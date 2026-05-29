#!/bin/bash
# Second-line defense: ensures claude.10s.sh becomes/stays visible after SwiftBar starts.
# Triggered by LaunchAgent at login (RunAtLoad) and every 5 minutes (StartInterval).
#
# VisibleCC semantics (empirical): "1" = item shown in the menu bar, "0"/absent = hidden.
# The value takes several seconds to settle after a SwiftBar (re)launch, so every
# visibility judgement polls with a grace window instead of reading the key once —
# a single read right after launch reports a stale "0" and caused the old watchdog to
# "fix" blindly every cycle without ever confirming the icon actually came back.

PLUGIN="claude.10s.sh"
BUNDLE="com.ameba.SwiftBar"
COOLDOWN_FILE="/tmp/.swiftbar-claude-watchdog-ts"
COOLDOWN_SEC=270
MAX_ATTEMPTS=2
SETTLE_SEC=25          # how long to wait for VisibleCC to settle after a (re)launch
LOG="/tmp/swiftbar-watchdog.log"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts): $*" >> "$LOG"; }

visible_now() {
    [ "$(defaults read "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" 2>/dev/null | tr -d ' ')" = "1" ]
}

# Poll VisibleCC for up to SETTLE_SEC; succeed as soon as it reports visible.
wait_visible() {
    for _ in $(seq 1 "$SETTLE_SEC"); do
        visible_now && return 0
        sleep 1
    done
    return 1
}

# Cooldown is set only after we GIVE UP, so a successful fix never blocks the next check.
if [ -f "$COOLDOWN_FILE" ]; then
    now=$(date +%s)
    last=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    (( now - last < COOLDOWN_SEC )) && exit 0
fi

# Wait for SwiftBar to be running (up to 2 minutes — needed at boot).
for _ in $(seq 1 24); do
    pgrep -x SwiftBar > /dev/null && break
    sleep 5
done
pgrep -x SwiftBar > /dev/null || exit 0

# Already visible (within the grace window)? Nothing to do.
wait_visible && exit 0

log "claude.10s.sh hidden (VisibleCC!=1), applying fix"

attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
    # killall -9 required — osascript quit leaves the PID alive (confirmed empirically).
    killall -9 SwiftBar 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8; do pgrep -q SwiftBar || break; sleep 0.5; done

    # Write BOTH: Preferred Position (prevents overflow) + VisibleCC (prevents hiding).
    defaults write "$BUNDLE" "NSStatusItem Preferred Position $PLUGIN" -float 700
    defaults write "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" -bool YES
    open -a SwiftBar

    # Verify the icon actually came back before declaring success.
    if wait_visible; then
        log "fix succeeded on attempt $attempt/$MAX_ATTEMPTS (VisibleCC=1)"
        rm -f "$COOLDOWN_FILE"
        exit 0
    fi
    log "attempt $attempt/$MAX_ATTEMPTS did not stick within ${SETTLE_SEC}s"
    (( attempt++ ))
done

# Still hidden after all attempts — back off so we don't thrash SwiftBar until next interval.
log "gave up after $MAX_ATTEMPTS attempts; cooling down ${COOLDOWN_SEC}s"
date +%s > "$COOLDOWN_FILE"
