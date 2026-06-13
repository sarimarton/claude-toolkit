#!/bin/bash
# Second-line defense: ensures claude.10s.sh stays alive in the menu bar.
# Triggered by LaunchAgent at login (RunAtLoad) and every 5 minutes (StartInterval).
#
# Three failure modes are covered:
#   1. SwiftBar not running          → relaunch lightly (no kill).
#   2. Running but item HIDDEN       → per-plugin disable/enable cycle (see below).
#   3. Running but wedged (no ticks) → hard restart (killall -9, last resort).
#
# The hidden-item mode (2) is SwiftBar v2.0.1's upstream bug #442/#429: when the
# app hides a status item (empty output tick, transient plugin-reload glitch),
# AppKit persists "NSStatusItem VisibleCC <plugin>" = 0 and deletes the
# "Preferred Position" key. From then on every relaunch recreates the item
# already-hidden — the plugin keeps ticking (fresh heartbeat), SwiftBar runs,
# but the icon is gone until the key is cleared. Fixed upstream only in
# v2.1.0-beta (cc768bb, PR #458), so we emulate the fix here: DELETE the
# visibility key (key-absent = default-visible; writing YES is wrong, the next
# hide just flips it back) while the item does not exist, i.e. between a
# swiftbar://disableplugin and enableplugin pair. That rebuilds only OUR item;
# killall -9 would blank every SwiftBar plugin for ~25s, so it stays reserved
# for the wedged case.
#
# History notes:
#   - VisibleCC was once observed reading 0 while the icon was visible, which
#     made a VisibleCC-triggered killall thrash everything. The remedy here is
#     therefore per-plugin, verified after the fact, and rate-limited
#     (RESHOW_COOLDOWN_SEC) — a false positive costs a brief flicker, not a bar
#     blackout. Forensics (2026-06-10) confirmed VisibleCC=0 + missing
#     Preferred Position is the genuine AppKit removal signature.
#   - The old "first run since boot" unconditional killall+restart is GONE: it
#     blanked the bar at every boot and the state it guarded against (running +
#     ticking + hidden) is exactly what the VisibleCC check now detects.

PLUGIN="claude.10s.sh"
BUNDLE="com.ameba.SwiftBar"
HEARTBEAT="/tmp/claude-menu-raw.txt"
HEARTBEAT_MAX_AGE=60   # plugin ticks every ~10s; >60s stale ⇒ SwiftBar not ticking
COOLDOWN_FILE="/tmp/.swiftbar-claude-watchdog-ts"
COOLDOWN_SEC=270
RESHOW_TS="/tmp/.swiftbar-claude-reshow-ts"
RESHOW_COOLDOWN_SEC=600
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

# Mirror upstream v2.1.0's cleanupStatusItemVisibility, scoped to our plugin:
# delete the hidden flag (both macOS spellings) so the item is recreated
# visible, and re-assert the position (a plain write — AppKit preserves it).
clear_visibility_keys() {
    defaults delete "$BUNDLE" "NSStatusItem VisibleCC $PLUGIN" 2>/dev/null || true
    defaults delete "$BUNDLE" "NSStatusItem Visible $PLUGIN" 2>/dev/null || true
    defaults write "$BUNDLE" "NSStatusItem Preferred Position $PLUGIN" -float "$PREFERRED_POS"
}

# Hard restart — wedged SwiftBar only. The defaults surgery happens AFTER the
# kill and BEFORE the relaunch, so no running instance can clobber it and the
# fresh instance reads the cleaned state at item creation.
hard_restart() {
    # killall -9 required — osascript quit leaves the PID alive (confirmed empirically).
    killall -9 SwiftBar 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8; do pgrep -q SwiftBar || break; sleep 0.5; done
    clear_visibility_keys
    open -a SwiftBar
}

# Rebuild only our status item: disabling the plugin deallocates its
# NSStatusItem, so the defaults surgery lands while nothing owns the keys;
# enabling recreates the item, which reads the cleaned (absent ⇒ visible)
# state. Other SwiftBar plugins stay on the bar throughout.
reshow_item() {
    open -g "swiftbar://disableplugin?plugin=$PLUGIN" || return 1
    sleep 1
    clear_visibility_keys
    open -g "swiftbar://enableplugin?plugin=$PLUGIN" || return 1
    sleep 5
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
    # Case 2: running and ticking, but AppKit has the item flagged hidden.
    if [ "$(visible_cc)" = "0" ]; then
        now=$(date +%s)
        last_reshow=$(cat "$RESHOW_TS" 2>/dev/null || echo 0)
        (( now - last_reshow < RESHOW_COOLDOWN_SEC )) && exit 0
        date +%s > "$RESHOW_TS"
        log "item hidden (VisibleCC=0) — rebuilding via disable/enable cycle"
        reshow_item
        if [ "$(visible_cc)" != "0" ]; then
            log "reshow succeeded (VisibleCC=$(visible_cc))"
        else
            log "reshow did not stick — hard restart"
            hard_restart
            wait_heartbeat || true
            log "post-restart VisibleCC=$(visible_cc)"
        fi
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
