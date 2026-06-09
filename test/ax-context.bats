#!/usr/bin/env bats
# ax-context: synchronous utility that reads the focused app's focused-element text
# via AppleScript (System Events / AX). The OS/AppleScript call itself is not
# unit-testable, so we inject a fake `osascript` (DICT_OSASCRIPT_BIN) that returns
# canned AX output, and test the WRAPPER logic: trimming, byte-cap, empty handling,
# and the optional app-name header.

setup() {
  TESTDIR="$(mktemp -d)"
  BIN="$TESTDIR/bin"; mkdir -p "$BIN"
  TPL="$BATS_TEST_DIRNAME/../src/modules/dictation-pipeline/assets/ax-context.sh.tpl"
  AXC="$TESTDIR/ax-context.sh"
  sed "s#{{home}}#$TESTDIR#g" "$TPL" > "$AXC"
  chmod +x "$AXC"
}
teardown() { rm -rf "$TESTDIR"; }

# Make a fake osascript that prints $AX_FAKE_OUT and exits $AX_FAKE_RC.
mk_osascript() {
  cat > "$BIN/osascript" <<EOF
#!/usr/bin/env bash
[ -n "\${AX_FAKE_OUT+x}" ] && printf '%s' "\$AX_FAKE_OUT"
exit \${AX_FAKE_RC:-0}
EOF
  chmod +x "$BIN/osascript"
}

run_axc() {
  AX_FAKE_OUT="$1" AX_FAKE_RC="${2:-0}" DICT_OSASCRIPT_BIN="$BIN/osascript" \
    run "$AXC" "${@:3}"
}

@test "prints the focused element text from AppleScript" {
  mk_osascript
  run_axc "hello from the focused field"
  [ "$status" -eq 0 ]
  [ "$output" = "hello from the focused field" ]
}

@test "trims leading/trailing whitespace" {
  mk_osascript
  run_axc "   padded text   "
  [ "$status" -eq 0 ]
  [ "$output" = "padded text" ]
}

@test "preserves internal newlines and Hungarian accents" {
  mk_osascript
  printf -v payload 'első sor\nmásodik árvíztűrő sor'
  run_axc "$payload"
  [ "$status" -eq 0 ]
  [ "$output" = "$payload" ]
}

@test "empty AX value yields empty output and success (not an error)" {
  mk_osascript
  run_axc ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "caps output to the byte limit (default ~4096)" {
  mk_osascript
  big="$(printf 'x%.0s' $(seq 1 6000))"   # 6000 chars
  run_axc "$big"
  [ "$status" -eq 0 ]
  [ "${#output}" -le 4096 ]
  # Cap keeps the TAIL (most recent on-screen context), so it ends in x.
  [ "${output: -1}" = "x" ]
}

@test "osascript failure (no AX permission / no focused element) -> empty, rc 0" {
  mk_osascript
  AX_FAKE_OUT="" AX_FAKE_RC=1 DICT_OSASCRIPT_BIN="$BIN/osascript" run "$AXC"
  # The utility must degrade gracefully: no context is not a hard failure.
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- chrome filtering for Electron apps (Claude Desktop) ----------------------
# The AppleScript returns the whole window's AXStaticText, which is contaminated
# with sidebar/nav/action chrome. The wrapper must strip a known UI blocklist and
# dedupe the "Claude responded:"/"You said:" summary-vs-body doubling.

@test "strips Claude Desktop UI chrome (blocklist lines)" {
  mk_osascript
  printf -v payload '%s\n' \
    'Skip to content' 'Resize sidebar' 'Collapse sidebar' 'Search' \
    'New chat' 'Projects' 'Artifacts' 'Recents' 'View all' \
    'Ez egy valódi üzenet a beszélgetésből.' \
    'Copy' 'Retry' 'Read aloud' 'Message actions' 'Write a message…'
  run_axc "$payload"
  [ "$status" -eq 0 ]
  # Only the real message survives.
  [ "$output" = "Ez egy valódi üzenet a beszélgetésből." ]
}

@test "drops 'Claude responded:' and 'You said:' summary lines" {
  mk_osascript
  printf -v payload '%s\n' \
    'You said: Mi a koprofágia?' \
    'Mi a koprofágia?' \
    'Claude responded: A koprofágia a saját…' \
    'A koprofágia a saját ürülék fogyasztása.'
  run_axc "$payload"
  [ "$status" -eq 0 ]
  # Summary/anchor lines removed; bodies kept.
  [[ "$output" == *"Mi a koprofágia?"* ]]
  [[ "$output" == *"A koprofágia a saját ürülék fogyasztása."* ]]
  [[ "$output" != *"You said:"* ]]
  [[ "$output" != *"Claude responded:"* ]]
}

@test "dedupes consecutive identical lines (label-then-value doubling)" {
  mk_osascript
  printf -v payload '%s\n' \
    'ugyanaz a sor' 'ugyanaz a sor' 'más sor'
  run_axc "$payload"
  [ "$status" -eq 0 ]
  # 'ugyanaz a sor' appears once, not twice.
  [ "$(printf '%s\n' "$output" | grep -c 'ugyanaz a sor')" -eq 1 ]
}

@test "real conversation text survives chrome filtering" {
  mk_osascript
  printf -v payload '%s\n' \
    'Recents' 'Skip to content' \
    'You said: add hozzá egy tesztet' \
    'add hozzá egy tesztet' \
    'Write a message…' 'Opus 4.8'
  run_axc "$payload"
  [ "$status" -eq 0 ]
  [ "$output" = "add hozzá egy tesztet" ]
}
