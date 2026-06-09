#!/usr/bin/env bats
# JSON-building arg-safety for meta.json and the /cleanup request body.
# Adversarial inputs: double quotes, single quotes, backticks, $, newlines,
# backslashes, and Hungarian accented multibyte chars must round-trip intact.

setup() {
  TESTDIR="$(mktemp -d)"
  TPL="$BATS_TEST_DIRNAME/../src/modules/dictation-pipeline/assets/dictation-json.sh.tpl"
  LIB="$TESTDIR/dictation-json.sh"
  sed 's#{{home}}#'"$TESTDIR"'#g; s#{{jq}}#'"$(command -v jq)"'#g' "$TPL" > "$LIB"
  source "$LIB"
}
teardown() { rm -rf "$TESTDIR"; }

@test "meta_json builds valid JSON with simple fields" {
  out="$(meta_json "1234-5" "%1618" "some context" "true" "auto")"
  echo "$out" | jq -e . >/dev/null            # valid JSON
  [ "$(echo "$out" | jq -r .id)" = "1234-5" ]
  [ "$(echo "$out" | jq -r .pane_id)" = "%1618" ]
  [ "$(echo "$out" | jq -r .send_enter)" = "true" ]   # boolean, not string
  [ "$(echo "$out" | jq -r .lang)" = "auto" ]
}

@test "meta_json preserves double quotes in context" {
  ctx='He said "hello" and ran make'
  out="$(meta_json "id" "%1" "$ctx" "false" "auto")"
  echo "$out" | jq -e . >/dev/null
  [ "$(echo "$out" | jq -r .pane_context)" = "$ctx" ]
}

@test "meta_json preserves shell-special chars (backtick, dollar, paren)" {
  ctx='run `whoami` and $(date) costs $5'
  out="$(meta_json "id" "%1" "$ctx" "false" "auto")"
  echo "$out" | jq -e . >/dev/null
  [ "$(echo "$out" | jq -r .pane_context)" = "$ctx" ]
}

@test "meta_json preserves newlines in context" {
  ctx="$(printf 'line one\nline two\nline three')"
  out="$(meta_json "id" "%1" "$ctx" "false" "auto")"
  echo "$out" | jq -e . >/dev/null
  [ "$(echo "$out" | jq -r .pane_context)" = "$ctx" ]
}

@test "meta_json preserves Hungarian accented characters" {
  ctx='Árvíztűrő tükörfúrógép — őúéáíóüóőű'
  out="$(meta_json "id" "%1" "$ctx" "false" "auto")"
  echo "$out" | jq -e . >/dev/null
  [ "$(echo "$out" | jq -r .pane_context)" = "$ctx" ]
}

@test "meta_json preserves backslashes" {
  ctx='path C:\Users\x and regex \d+\.\d+'
  out="$(meta_json "id" "%1" "$ctx" "false" "auto")"
  echo "$out" | jq -e . >/dev/null
  [ "$(echo "$out" | jq -r .pane_context)" = "$ctx" ]
}

@test "send_enter is a JSON boolean for both true and false" {
  t="$(meta_json "id" "%1" "ctx" "true" "auto")"
  f="$(meta_json "id" "%1" "ctx" "false" "auto")"
  [ "$(echo "$t" | jq -r '.send_enter | type')" = "boolean" ]
  [ "$(echo "$f" | jq -r '.send_enter | type')" = "boolean" ]
}

@test "cleanup_body builds {text,context} JSON with adversarial transcript" {
  txt='ez egy "teszt" `cmd` $(x)'
  ctx="$(printf 'tmux pane\nwith \"quotes\" and áccent')"
  out="$(cleanup_body "$txt" "$ctx")"
  echo "$out" | jq -e . >/dev/null
  [ "$(echo "$out" | jq -r .text)" = "$txt" ]
  [ "$(echo "$out" | jq -r .context)" = "$ctx" ]
}
