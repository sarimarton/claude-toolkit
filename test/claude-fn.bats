#!/usr/bin/env bats
# claude-fn: the dual-config claude() shell function.
#
# REGRESSION under test (TCC folder-prompt flood RCA):
#   The function must resolve the TCC-stable launcher path INSIDE the function
#   body on every call — NOT rely on a top-level `CLAUDE_BIN=` assignment. The
#   reason: Claude Code freezes the function definition into a shell-snapshot,
#   but the top-level assignment is fragile across snapshotting / stale
#   snapshots. If the function trusts an inherited (possibly empty/stale)
#   global $CLAUDE_BIN, a subprocess launched from a snapshot shell can fall
#   through to ~/.local/bin/claude (the versioned path) → the background daemon
#   pins to versions/<X> → TCC re-prompts on every update.
#
#   So: with the stable launcher present, claude() MUST exec the stable path
#   EVEN WHEN the ambient $CLAUDE_BIN is unset.

setup() {
  TESTDIR="$(mktemp -d)"
  TPL="$BATS_TEST_DIRNAME/../src/modules/dual-config/assets/claude-fn.sh.tpl"

  SCRIPTS_DIR="$TESTDIR/scripts"
  mkdir -p "$SCRIPTS_DIR"

  # Mock the stable launcher and the version symlink. Each echoes a tag so we
  # can assert WHICH path the function chose.
  STABLE="$SCRIPTS_DIR/claude-stable"
  VERSIONED="$TESTDIR/versioned-claude"
  printf '#!/usr/bin/env bash\necho STABLE\n' > "$STABLE"
  printf '#!/usr/bin/env bash\necho VERSIONED\n' > "$VERSIONED"
  chmod +x "$STABLE" "$VERSIONED"

  # Render the template: {{scripts_dir}} → stable launcher dir, {{claude}} →
  # the versioned fallback, {{jq}} → real jq path (unused in OAuth path).
  RENDERED="$TESTDIR/claude-fn.sh"
  sed -e "s#{{scripts_dir}}#$SCRIPTS_DIR#g" \
      -e "s#{{claude}}#$VERSIONED#g" \
      -e "s#{{jq}}#/usr/bin/jq#g" \
      "$TPL" > "$RENDERED"

  export HOME="$TESTDIR"
  mkdir -p "$HOME/.claude"
  echo '{}' > "$HOME/.claude/settings.json"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "claude() execs the stable launcher when sourced normally" {
  run bash -c "source '$RENDERED'; claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *STABLE* ]]
  [[ "$output" != *VERSIONED* ]]
}

@test "claude() execs the stable launcher EVEN WHEN ambient \$CLAUDE_BIN is empty (stale-snapshot guard)" {
  # Simulate a stale shell-snapshot: the function definition is in scope but the
  # top-level CLAUDE_BIN assignment did NOT carry over (CLAUDE_BIN inherited empty).
  run bash -c "source '$RENDERED'; CLAUDE_BIN=''; claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *STABLE* ]]
  [[ "$output" != *VERSIONED* ]]
}

@test "claude() falls back to the versioned path only when the stable launcher is absent" {
  rm -f "$STABLE"
  run bash -c "source '$RENDERED'; CLAUDE_BIN=''; claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *VERSIONED* ]]
}
