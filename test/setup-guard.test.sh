#!/usr/bin/env bash
# Tests for the setup.sh deploy-target guard (needs_deploy_target_confirmation).
#
# The guard protects against the "dev clone becomes deploy target" trap: running
# ./setup.sh from inside a development clone (e.g. ~/repos/claude-toolkit) would
# otherwise wire that working tree as the install dir, so `claude-toolkit update`
# would `git reset --hard` the user's dev repo. We want a y/N confirmation in that
# case — but NOT when the user opts in explicitly (CLAUDE_TOOLKIT_DIR set, --yes,
# or running from the canonical deploy location).

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../setup-guard.sh
. "$REPO_ROOT/setup-guard.sh"

CANONICAL="$HOME/.local/share/claude-toolkit"
pass=0; fail=0

# needs_deploy_target_confirmation <script_dir> <canonical_deploy_dir> <explicit_dir> <assume_yes>
# returns 0 (true) when a confirmation prompt is warranted.
check() {
  desc="$1"; expected="$2"; shift 2
  if needs_deploy_target_confirmation "$@"; then actual=0; else actual=1; fi
  if [ "$actual" -eq "$expected" ]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$desc"
  else
    fail=$((fail+1)); printf '  FAIL %s (expected ret=%s, got ret=%s)\n' "$desc" "$expected" "$actual"
  fi
}

echo "needs_deploy_target_confirmation:"

# Dev clone as script dir, no opt-in → MUST confirm (the trap case)
check "dev repo, no opt-in → confirm" 0 "$HOME/repos/claude-toolkit" "$CANONICAL" "" "false"

# Canonical deploy location → no confirm (normal fresh install / curl|sh path)
check "canonical deploy dir → no confirm" 1 "$CANONICAL" "$CANONICAL" "" "false"

# Explicit CLAUDE_TOOLKIT_DIR set → user opted in, no confirm even from dev repo
check "explicit CLAUDE_TOOLKIT_DIR → no confirm" 1 "$HOME/repos/claude-toolkit" "$CANONICAL" "$HOME/somewhere" "false"

# --yes / assume-yes → no interactive confirm even from dev repo
check "assume-yes → no confirm" 1 "$HOME/repos/claude-toolkit" "$CANONICAL" "" "true"

# Some other non-canonical dir (e.g. /tmp/checkout) → also confirm
check "arbitrary non-canonical dir → confirm" 0 "/tmp/claude-toolkit-checkout" "$CANONICAL" "" "false"

echo ""
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
