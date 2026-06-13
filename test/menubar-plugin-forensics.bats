#!/usr/bin/env bats
# Forensics logging in claude.10s.sh.tpl — every anomalous plugin run must leave
# a trace (the 2026-06-13 icon disappearance had none). Covers: log format,
# size-capped rotation, abnormal-exit trap, and the display path's serve/fallback
# behavior (empty stdout is what makes SwiftBar hide the item).

setup() {
  WORK="$BATS_TEST_TMPDIR"
  TPL="$BATS_TEST_DIRNAME/../src/modules/menubar/assets/claude.10s.sh.tpl"
  SCRIPT="$WORK/claude.10s.sh"
  sed -e "s|{{home}}|$WORK/home|g" \
      -e "s|{{scripts_dir}}|$WORK/scripts|g" \
      -e "s|{{config_file}}|$WORK/config.yaml|g" \
      -e "s|{{tmux}}|/usr/bin/true|g" \
      -e "s|{{yq}}|/usr/bin/true|g" \
      "$TPL" > "$SCRIPT"
  chmod +x "$SCRIPT"
  LOG="$WORK/home/.config/claude-toolkit/state/menubar-plugin.log"
  # Hermetic seams: never touch the real /tmp cache/lock of the running menubar.
  export CLAUDE_MENU_CACHE="$WORK/cache.txt"
  export CLAUDE_MENU_RENDER_LOCK="$WORK/render.lock"
  # A live PID in the lock makes _spawn_bg_render a no-op (no heavy bg render).
  echo $$ > "$WORK/render.lock"
}

@test "_plugin_log writes a timestamped entry into the state-dir log" {
  run bash -c "source '$SCRIPT'; _plugin_log 'hello forensics'"
  [ "$status" -eq 0 ]
  [ -f "$LOG" ]
  grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[display pid=[0-9]+\] hello forensics$' "$LOG"
}

@test "_plugin_log rotates the log once it exceeds the size cap" {
  mkdir -p "${LOG%/*}"
  # Build an oversized log (> 256 KiB) of recognizable filler lines.
  yes 'old filler line for rotation test' | head -c 300000 > "$LOG"
  run bash -c "source '$SCRIPT'; _plugin_log 'post-rotation entry'"
  [ "$status" -eq 0 ]
  size=$(stat -f %z "$LOG")
  [ "$size" -lt 262144 ]
  grep -q 'post-rotation entry' "$LOG"
}

@test "non-zero exit is logged with rc and the last failing command" {
  run bash -c "source '$SCRIPT'; /usr/bin/false; exit 3"
  [ "$status" -eq 3 ]
  grep -q 'ABNORMAL exit rc=3' "$LOG"
  grep -q '/usr/bin/false' "$LOG"
}

@test "clean exit logs nothing" {
  run bash -c "source '$SCRIPT'; exit 0"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ] || ! grep -q 'ABNORMAL' "$LOG"
}

@test "display path serves the cache verbatim and exits 0" {
  printf 'CACHED LINE | size=12\n---\nmenu item\n' > "$WORK/cache.txt"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "CACHED LINE | size=12" ]
  [ ! -f "$LOG" ] || ! grep -q 'ABNORMAL' "$LOG"
}

@test "display path without cache emits a non-empty placeholder and logs the event" {
  rm -f "$WORK/cache.txt"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  grep -q 'no cache' "$LOG"
}
