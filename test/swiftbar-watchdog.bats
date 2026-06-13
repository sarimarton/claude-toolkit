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
