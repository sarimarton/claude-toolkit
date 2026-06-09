#!/usr/bin/env bats
# Delivery / send-keys escaping — the highest-risk correctness surface.
# A fake `tmux` shim on PATH records every invocation's argv so we can assert
# the EXACT argument vector. The dictated text must reach the pane verbatim via
# `send-keys -t <pane> -l -- <text>` (literal, no interpretation), and Enter must
# be a SEPARATE call WITHOUT -l (the Enter key, not the literal word "Enter").

setup() {
  TESTDIR="$(mktemp -d)"
  BIN="$TESTDIR/bin"; mkdir -p "$BIN"
  ARGLOG="$TESTDIR/tmux-args.log"
  export ARGLOG

  # Fake tmux: append one NUL-delimited record per call, then a newline separator.
  # Records argv exactly so we can detect any extra escaping/splitting.
  cat > "$BIN/tmux" <<'SHIM'
#!/usr/bin/env bash
{
  printf 'CALL'
  for a in "$@"; do printf '\037%s' "$a"; done   # 0x1f unit-separator between args
  printf '\n'
} >> "$ARGLOG"
# Emulate the pane-existence check: `list-panes -a -F '#{pane_id}'` prints the
# pane ids that exist. We echo the ids the tests use so the guard passes.
case "$1" in
  list-panes) printf '%%1\n%%2\n%%1618\n'; exit 0 ;;
  has-session|display-message) exit 0 ;;
esac
exit 0
SHIM
  chmod +x "$BIN/tmux"

  # Render the deliver script with the shim's tmux and a tmp queue root.
  TPL="$BATS_TEST_DIRNAME/../src/modules/dictation-pipeline/assets/dictation-deliver.sh.tpl"
  DELIVER="$TESTDIR/dictation-deliver.sh"
  sed 's#{{tmux}}#'"$BIN/tmux"'#g; s#{{jq}}#'"$(command -v jq)"'#g; s#{{home}}#'"$TESTDIR"'#g' "$TPL" > "$DELIVER"
  chmod +x "$DELIVER"

  QROOT="$TESTDIR/dictation"
  mkdir -p "$QROOT/jobs/processing"
}
teardown() { rm -rf "$TESTDIR"; }

# Create a processing job dir with given cleaned text + send_enter.
mk_job() {
  local id="$1" text="$2" send_enter="$3" pane="${4:-%1}"
  local d="$QROOT/jobs/processing/$id"
  mkdir -p "$d"
  printf '%s' "$text" > "$d/cleaned.txt"
  "$(command -v jq)" -n --arg p "$pane" --argjson e "$send_enter" \
    '{pane_id:$p, send_enter:$e}' > "$d/meta.json"
  printf '%s' "$d"
}

# Extract the Nth CALL's args as NUL... -> print one arg per line.
# Args are 0x1f-separated; we translate to newlines for assertion.
call_args() {
  local n="$1"
  sed -n "${n}p" "$ARGLOG" | sed 's/^CALL//' | tr '\037' '\n' | sed '1d'
}

@test "literal text is sent via send-keys -t <pane> -l -- <text>" {
  d="$(mk_job job1 "hello world" true)"
  DICT_QUEUE_ROOT="$QROOT" run "$DELIVER" "$d"
  [ "$status" -eq 0 ]
  # First send-keys call: the literal text.
  # Find the call that contains -l and the text.
  grep -q -- '-l' "$ARGLOG"
  # The args of the literal call must be: send-keys -t %1 -l -- hello world
  line="$(grep -- '-l' "$ARGLOG" | head -1)"
  echo "$line" | grep -q 'send-keys'
  echo "$line" | grep -q '%1'
  echo "$line" | grep -q -- '--'
  # The literal text "hello world" is a single argv element (not split).
  printf '%s' "$line" | tr '\037' '\n' | grep -qx 'hello world'
}

@test "Enter is a SEPARATE call without -l when send_enter=true" {
  d="$(mk_job job2 "do it" true)"
  DICT_QUEUE_ROOT="$QROOT" run "$DELIVER" "$d"
  [ "$status" -eq 0 ]
  # There must be a send-keys call whose last arg is exactly "Enter" and which does NOT carry -l.
  enter_line="$(grep 'Enter' "$ARGLOG" | head -1)"
  [ -n "$enter_line" ]
  echo "$enter_line" | grep -q 'send-keys'
  ! printf '%s' "$enter_line" | tr '\037' '\n' | grep -qx -- '-l'
  printf '%s' "$enter_line" | tr '\037' '\n' | grep -qx 'Enter'
}

@test "NO Enter call when send_enter=false" {
  d="$(mk_job job3 "no submit" false)"
  DICT_QUEUE_ROOT="$QROOT" run "$DELIVER" "$d"
  [ "$status" -eq 0 ]
  # The literal text call happened, but no standalone Enter key call.
  ! grep -qE '\037Enter$' "$ARGLOG"
}

@test "shell metacharacters reach the pane verbatim (no expansion/splitting)" {
  payload='x; rm -rf / $(whoami) `id` && echo "q" | cat'
  d="$(mk_job job4 "$payload" false)"
  DICT_QUEUE_ROOT="$QROOT" run "$DELIVER" "$d"
  [ "$status" -eq 0 ]
  # The entire payload must appear as ONE argv element verbatim.
  printf '%s' "$(grep -- '-l' "$ARGLOG" | head -1)" | tr '\037' '\n' | grep -qxF -e "$payload"
}

@test "leading-dash text is protected by -- (not parsed as a flag)" {
  payload='--force -rf -t bad'
  d="$(mk_job job5 "$payload" false)"
  DICT_QUEUE_ROOT="$QROOT" run "$DELIVER" "$d"
  [ "$status" -eq 0 ]
  printf '%s' "$(grep -- '-l' "$ARGLOG" | head -1)" | tr '\037' '\n' | grep -qxF -e "$payload"
}

@test "Hungarian accents reach the pane verbatim" {
  payload='Árvíztűrő tükörfúrógép őúéáíóüóőű'
  d="$(mk_job job6 "$payload" true)"
  DICT_QUEUE_ROOT="$QROOT" run "$DELIVER" "$d"
  [ "$status" -eq 0 ]
  printf '%s' "$(grep -- '-l' "$ARGLOG" | head -1)" | tr '\037' '\n' | grep -qxF -e "$payload"
}
