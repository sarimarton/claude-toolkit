#!/usr/bin/env bats
# Watchdog logging — the log must survive reboots (state dir, not /tmp) and be
# size-capped, so a disappearance weeks later still has a paper trail.

setup() {
  WORK="$BATS_TEST_TMPDIR"
  TPL="$BATS_TEST_DIRNAME/../src/modules/menubar/assets/swiftbar-watchdog.sh.tpl"
  SCRIPT="$WORK/swiftbar-watchdog.sh"
  sed -e "s|{{home}}|$WORK/home|g" "$TPL" > "$SCRIPT"
  chmod +x "$SCRIPT"
  LOG="$WORK/home/.config/claude-toolkit/state/swiftbar-watchdog.log"
}

@test "log() writes a timestamped entry into the state-dir log" {
  run bash -c "source '$SCRIPT'; log 'hello watchdog'"
  [ "$status" -eq 0 ]
  [ -f "$LOG" ]
  grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}: hello watchdog$' "$LOG"
}

@test "log() rotates the log once it exceeds the size cap" {
  mkdir -p "${LOG%/*}"
  yes 'old watchdog filler line' | head -c 300000 > "$LOG"
  run bash -c "source '$SCRIPT'; log 'post-rotation entry'"
  [ "$status" -eq 0 ]
  size=$(stat -f %z "$LOG")
  [ "$size" -lt 262144 ]
  grep -q 'post-rotation entry' "$LOG"
}

# Build a runnable copy with all external side-effect commands stubbed so the
# top-level control flow can run hermetically. Each stub appends to $TRACE.
# Heartbeat freshness is driven through the REAL HEARTBEAT file (a freshly
# touched temp = healthy; a missing path = stale) rather than by overriding the
# heartbeat helpers, since the script redefines those after our stubs. $VCC
# drives the VisibleCC reading. $FRESH=1 makes the heartbeat fresh.
#
# SETTLE_SEC is forced to 1 so the stale path's wait_heartbeat loop returns
# fast instead of polling for 30s.
_make_stubbed() {
  STUB="$WORK/swiftbar-watchdog.run.sh"
  TRACE="$WORK/trace.log"
  HB_FILE="$WORK/heartbeat"
  : > "$TRACE"
  {
    echo '#!/bin/bash'
    echo "pgrep()  { echo 12345; return 0; }"          # SwiftBar always 'running'
    echo "killall() { echo \"killall \$*\" >> '$TRACE'; }"
    echo "open()    { echo \"open \$*\" >> '$TRACE'; }"
    echo "defaults(){ echo \"defaults \$*\" >> '$TRACE'; case \"\$1\" in read) [ \"\$VCC\" = absent ] && return 1 || { echo \"\$VCC\"; return 0; };; esac; return 0; }"
    # Strip shebang + source-seam early return so the body runs under our stubs,
    # and repoint HEARTBEAT/SETTLE_SEC at our hermetic fixtures.
    # Also repoint COOLDOWN_FILE into $WORK — the real path is a shared /tmp file
    # that a prior watchdog run (or another test) may have stamped, which would
    # trip the cooldown guard and short-circuit the script before it acts.
    grep -v '^#!/bin/bash' "$SCRIPT" \
      | grep -v '^return 0 2>/dev/null' \
      | sed -e "s|^HEARTBEAT=.*|HEARTBEAT='$HB_FILE'|" \
            -e "s|^SETTLE_SEC=.*|SETTLE_SEC=1|" \
            -e "s|^COOLDOWN_FILE=.*|COOLDOWN_FILE='$WORK/cooldown-ts'|"
  } > "$STUB"
  [ "${FRESH:-0}" = 1 ] && touch "$HB_FILE" || rm -f "$HB_FILE"
}

@test "hidden item (VisibleCC=0) is fixed by key-delete WITHOUT any restart" {
  FRESH=1 _make_stubbed
  VCC=0 run bash "$STUB"
  [ "$status" -eq 0 ]
  grep -q 'clearing visibility key (no restart)' "$LOG"
  # The whole point of the 2026-06-13 fix: never killall on a mere hidden flag.
  ! grep -q 'killall' "$TRACE"
  # And it must actually delete the key.
  grep -q 'defaults delete .*VisibleCC' "$TRACE"
}

@test "healthy + visible item is a no-op (no defaults writes, no restart)" {
  FRESH=1 _make_stubbed
  VCC=1 run bash "$STUB"
  [ "$status" -eq 0 ]
  ! grep -q 'killall' "$TRACE"
  ! grep -q 'defaults delete' "$TRACE"
}

@test "wedged SwiftBar (stale heartbeat) DOES hard-restart" {
  FRESH=0 _make_stubbed   # missing heartbeat ⇒ stale ⇒ case 3
  VCC=absent run bash "$STUB"
  [ "$status" -eq 0 ]
  grep -q 'heartbeat stale' "$LOG"
  grep -q 'killall' "$TRACE"
}
