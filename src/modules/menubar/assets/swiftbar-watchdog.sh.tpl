#!/bin/bash
# Second-line defense: ensures claude.10s.sh stays alive in the menu bar.
# Triggered by LaunchAgent at login (RunAtLoad) and every 5 minutes (StartInterval).
#
# Detection uses a liveness HEARTBEAT, not NSStatusItem VisibleCC.
#
# Why not VisibleCC: empirically it reads "0" even while the icon is visibly
# present, so the previous watchdog concluded "hidden" on every single 5-min
# cycle and killall-ed SwiftBar each time. That routine killall was itself the
# dominant cause of the icon — and every other SwiftBar plugin — vanishing for
# ~25s. We instead trust two real signals:
#   1. Is SwiftBar running at all?  → if not, just relaunch it (light, no kill).
#   2. Is the plugin actually being ticked?  → the menu plugin rewrites its output
#      cache (/tmp/claude-menu-raw.txt) on every ~10s background tick, so a stale
#      mtime means SwiftBar is wedged and a hard restart is warranted.
# killall -9 is reserved for case 2 (running-but-wedged) — never the routine action.

PLUGIN="claude.10s.sh"
BUNDLE="com.ameba.SwiftBar"
HEARTBEAT="/tmp/claude-menu-raw.txt"
HEARTBEAT_MAX_AGE=60   # plugin ticks every ~10s; >60s stale ⇒ SwiftBar not ticking
COOLDOWN_FILE="/tmp/.swiftbar-claude-watchdog-ts"
COOLDOWN_SEC=270
SETTLE_SEC=30          # max wait for the heartbeat to resume after a (re)launch
LOG="/tmp/swiftbar-watchdog.log"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts): $*" >> "$LOG"; }

# Heartbeat age in seconds (large number when the cache file is missing).
heartbeat_age() {
    local m
    m=$(stat -f %m "$HEARTBEAT" 2>/dev/null) || { echo 999999; return; }
    echo $(( $(date +%s) - m ))
}

# Poll the heartbeat for up to SETTLE_SEC; succeed as soon as it is fresh.
wait_heartbeat() {
    for _ in $(seq 1 "$SETTLE_SEC"); do
        (( $(heartbeat_age) <= HEARTBEAT_MAX_AGE )) && return 0
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

# Case 1: SwiftBar not running (e.g. at boot). Relaunch lightly — no killall — and
# wait up to 2 minutes for it to come up (needed at login).
if ! pgrep -x SwiftBar > /dev/null; then
    log "SwiftBar not running — launching"
    open -a SwiftBar
    for _ in $(seq 1 24); do
        pgrep -x SwiftBar > /dev/null && break
        sleep 5
    done
fi
pgrep -x SwiftBar > /dev/null || { log "SwiftBar failed to start"; exit 0; }

# First run since boot: a reboot leaves SwiftBar running and the plugin ticking,
# yet the menu-bar item can come up unplaced/hidden — a state the heartbeat check
# below cannot detect (the plugin IS running, the cache IS fresh). So once per
# boot, re-assert the item's preferred position and hard-restart SwiftBar to force
# it back onto the bar. Boot-scoped via kern.boottime (compared to a marker mtime)
# so it fires exactly once per boot and never thrashes on the 5-min interval.
BOOT_MARKER="/tmp/.swiftbar-claude-watchdog-boot"
boot_epoch=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*{ *sec *= *\([0-9]*\).*/\1/p')
marker_mtime=0
[ -f "$BOOT_MARKER" ] && marker_mtime=$(stat -f %m "$BOOT_MARKER" 2>/dev/null || echo 0)
if [ -n "$boot_epoch" ] && (( marker_mtime < boot_epoch )); then
    : > "$BOOT_MARKER"   # mark before acting, so a crash mid-restart can't loop us
    log "first run since boot — asserting menu-bar placement + restarting SwiftBar"
    defaults write "$BUNDLE" "NSStatusItem Preferred Position $PLUGIN" -float 700
    defaults write "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" -bool YES
    killall -9 SwiftBar 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8; do pgrep -q SwiftBar || break; sleep 0.5; done
    open -a SwiftBar
    wait_heartbeat || true
    exit 0
fi

# Healthy if the plugin is ticking. A stale or just-launched state gets up to
# SETTLE_SEC to resume on its own before we resort to a hard restart — this
# absorbs a momentary tick hiccup or a fresh-launch warm-up without thrashing.
if (( $(heartbeat_age) <= HEARTBEAT_MAX_AGE )) || wait_heartbeat; then
    exit 0
fi

# Case 2: SwiftBar is running but wedged (heartbeat stale). Hard-restart.
log "heartbeat stale ($(heartbeat_age)s > ${HEARTBEAT_MAX_AGE}s) — restarting SwiftBar"
# killall -9 required — osascript quit leaves the PID alive (confirmed empirically).
killall -9 SwiftBar 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8; do pgrep -q SwiftBar || break; sleep 0.5; done
# Pin position + visibility on the way back up — harmless, helps avoid overflow.
defaults write "$BUNDLE" "NSStatusItem Preferred Position $PLUGIN" -float 700
defaults write "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" -bool YES
open -a SwiftBar

# Verify the plugin is actually ticking again before declaring success.
if wait_heartbeat; then
    log "restart succeeded (heartbeat resumed)"
    rm -f "$COOLDOWN_FILE"
    exit 0
fi

# Still wedged — back off so we don't thrash SwiftBar until the next interval.
log "heartbeat did not resume within ${SETTLE_SEC}s; cooling down ${COOLDOWN_SEC}s"
date +%s > "$COOLDOWN_FILE"
