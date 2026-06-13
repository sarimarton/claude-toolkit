#!/bin/bash
# Second-line defense: ensures claude.10s.sh stays alive in the menu bar.
# Triggered by LaunchAgent at login (RunAtLoad) and every 5 minutes (StartInterval).
#
# Three failure modes are covered:
#   1. SwiftBar not running          → relaunch lightly (no kill).
#   2. Running but item HIDDEN       → delete the visibility key (NO restart).
#   3. Running but wedged (no ticks) → hard restart (killall -9, last resort).
#
# The hidden-item mode (2) was SwiftBar v2.0.1's upstream bug #442/#429: when the
# app hid a status item (transient plugin-reload glitch), AppKit persisted
# "NSStatusItem VisibleCC <plugin>" = 0 and the item stayed gone across relaunches
# — the plugin kept ticking (fresh heartbeat), SwiftBar ran, but the icon was
# gone until the key was cleared. This is FIXED upstream in v2.1.0-beta-2 (build
# 576, #442 "system diagnostics" + cleanupStatusItemVisibility from beta-1): the
# app no longer persists the hidden flag, so VisibleCC stays `absent` and the
# item returns on its own. We require >= v2.1.0; mode 2 is now only a cheap
# belt-and-braces: if VisibleCC ever reads 0 we simply DELETE the key (key-absent
# = default-visible) and let the running app pick it up — NO disable/enable cycle,
# NO killall. The previous beta-less code did a per-hidden reshow that did not
# stick on 2.0.1 and fell through to killall -9 EVERY 10 min, blanking the whole
# bar for ~25s each time (forensics 2026-06-13). That thrash is gone: killall -9
# is reserved strictly for the wedged case (3).
#
# History notes:
#   - 2026-06-13: running 2.0.1, the reshow→hard-restart-on-hidden loop thrashed
#     the bar every 10 min. Root cause was twofold: 2.0.1 lacks the upstream fix
#     (so VisibleCC kept flipping to 0), and the watchdog escalated every 0 to a
#     killall. Resolved by upgrading SwiftBar to 2.1.0-beta-2 and demoting mode 2
#     to a no-restart key-delete.
#   - The old "first run since boot" unconditional killall+restart is GONE: it
#     blanked the bar at every boot and the state it guarded against (running +
#     ticking + hidden) is what the VisibleCC key-delete now handles harmlessly.

PLUGIN="claude.10s.sh"
BUNDLE="com.ameba.SwiftBar"
HEARTBEAT="/tmp/claude-menu-raw.txt"
HEARTBEAT_MAX_AGE=60   # plugin ticks every ~10s; >60s stale ⇒ SwiftBar not ticking
COOLDOWN_FILE="/tmp/.swiftbar-claude-watchdog-ts"
COOLDOWN_SEC=270
SETTLE_SEC=30          # max wait for the heartbeat to resume after a (re)launch
PREFERRED_POS=700      # distance from the right edge of the bar, in points
# Machine-local state dir (NOT /tmp: must survive reboots so a disappearance
# discovered days later still has history; NOT the iCloud state dir: diagnostics
# are per-machine). Size-capped so it can run unattended forever.
LOG="{{home}}/.config/claude-toolkit/state/swiftbar-watchdog.log"
LOG_MAX_BYTES=262144

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() {
    mkdir -p "${LOG%/*}" 2>/dev/null
    if (( $(stat -f %z "$LOG" 2>/dev/null || echo 0) > LOG_MAX_BYTES )); then
        tail -c $(( LOG_MAX_BYTES / 2 )) "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
    fi
    echo "$(ts): $*" >> "$LOG"
}

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

# AppKit-persisted visibility flag for our item. Prints the raw value
# ("0"/"1") or "absent" when the key does not exist (= default-visible).
visible_cc() {
    defaults read "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" 2>/dev/null || echo absent
}

# Delete the hidden flag (both macOS spellings) and re-assert the position.
# On v2.1.0+ the running app no longer re-persists the flag, so a plain delete
# is enough to bring a stray-hidden item back — no restart, no disable/enable.
clear_visibility_keys() {
    defaults delete "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" 2>/dev/null || true
    defaults delete "$BUNDLE" "NSStatusItem Visible $PLUGIN" 2>/dev/null || true
    defaults write "$BUNDLE" "NSStatusItem Preferred Position $PLUGIN" -float "$PREFERRED_POS"
}

# Hard restart — wedged SwiftBar only (case 3). The defaults surgery happens
# AFTER the kill and BEFORE the relaunch, so no running instance can clobber it
# and the fresh instance reads the cleaned state at item creation.
hard_restart() {
    # killall -9 required — osascript quit leaves the PID alive (confirmed empirically).
    killall -9 SwiftBar 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8; do pgrep -q SwiftBar || break; sleep 0.5; done
    clear_visibility_keys
    open -a SwiftBar
}

# Test seam: `source swiftbar-watchdog.sh` (bats) gets the helpers above and
# stops here, before any pgrep/defaults/open side effect. Executed normally,
# `return` fails (suppressed) and the script continues.
return 0 2>/dev/null || true

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

# Ticking? A stale or just-launched state gets up to SETTLE_SEC to resume on its
# own — this absorbs a momentary tick hiccup or a fresh-launch warm-up without
# thrashing. NOTE: a fresh heartbeat does NOT prove the icon is on the bar (the
# plugin ticks even while hidden), hence the visibility check below.
if (( $(heartbeat_age) <= HEARTBEAT_MAX_AGE )) || wait_heartbeat; then
    # Case 2: running and ticking, but AppKit has the item flagged hidden. On
    # v2.1.0+ this is rare and self-healing; a plain key-delete nudges it back.
    # NO restart and NO disable/enable cycle — escalating every 0 to a killall
    # is what thrashed the bar on 2.0.1 (forensics 2026-06-13).
    if [ "$(visible_cc)" = "0" ]; then
        log "item hidden (VisibleCC=0) — clearing visibility key (no restart)"
        clear_visibility_keys
    fi
    exit 0
fi

# Case 3: SwiftBar is running but wedged (heartbeat stale). Hard-restart.
log "heartbeat stale ($(heartbeat_age)s > ${HEARTBEAT_MAX_AGE}s) — restarting SwiftBar"
hard_restart

# Verify the plugin is actually ticking again before declaring success.
if wait_heartbeat; then
    log "restart succeeded (heartbeat resumed)"
    rm -f "$COOLDOWN_FILE"
    exit 0
fi

# Still wedged — back off so we don't thrash SwiftBar until the next interval.
log "heartbeat did not resume within ${SETTLE_SEC}s; cooling down ${COOLDOWN_SEC}s"
date +%s > "$COOLDOWN_FILE"
