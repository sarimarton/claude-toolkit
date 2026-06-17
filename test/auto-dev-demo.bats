#!/usr/bin/env bats
# Demo ceremony — when an auto-dev PR's last task completes, a feature (and ONLY
# a feature) should get a user-facing "how to try it" demo as the FINAL PR
# comment. Non-features (bugfix/refactor/infra) must NOT get a demo comment.
#
# The decision logic lives inside the auto-dev-cycle.yml workflow `run:` block as
# a sourceable function (emit_demo_or_ready_comment) so it can be tested
# hermetically here with `claude`/`gh` stubbed. We extract the function body from
# the YAML the same way the workflow shell would see it.

setup() {
  WORK="$BATS_TEST_TMPDIR"
  TPL="$BATS_TEST_DIRNAME/../src/modules/auto-dev/assets/auto-dev-cycle.yml.tpl"
  TRACE="$WORK/trace.log"
  : > "$TRACE"

  # Pull the function out of the YAML run-block. The function is delimited by
  # the marker comments below so the extractor is stable against surrounding
  # indentation/edits.
  LIB="$WORK/demo-lib.sh"
  awk '/# >>> demo-ceremony-fn >>>/{f=1;next} /# <<< demo-ceremony-fn <<</{f=0} f' \
    "$TPL" | sed 's/^            //' > "$LIB"

  # Sanity: extraction must have produced the function.
  grep -q 'emit_demo_or_ready_comment' "$LIB"

  STUBS="$WORK/stubs.sh"
  {
    echo "gh() { echo \"gh \$*\" >> '$TRACE'; }"
    # `claude` returns whatever DEMO_RESULT_JSON is set to, mimicking the
    # --output-format json envelope: {"structured_output": <obj>}.
    echo "claude() { echo \"claude \$*\" >> '$TRACE'; printf '%s' \"\$DEMO_RESULT_JSON\"; }"
  } > "$STUBS"
}

# Run the function with the given DEMO_RESULT_JSON envelope.
_run_fn() {
  DEMO_RESULT_JSON="$1" run bash -c "
    source '$STUBS'
    PR_NUMBER=42
    ISSUE_NUMBER=7
    WORK_DIR='$WORK'
    MODEL=sonnet
    CLAUDE_BIN=claude
    source '$LIB'
    emit_demo_or_ready_comment
  "
}

@test "non-feature (demo null) → only the plain ready-for-review comment, no demo" {
  _run_fn '{"structured_output":{"demo":null}}'
  [ "$status" -eq 0 ]
  # The plain ready comment went out.
  grep -q 'All tasks complete. Ready for review.' "$TRACE"
  # Exactly one PR comment was posted (the ready one) — no demo comment.
  # (Match only `gh pr comment` invocations, not the prompt text passed to claude.)
  [ "$(grep -c '^gh pr comment' "$TRACE")" -eq 1 ]
}

@test "feature (demo present) → demo posted as the FINAL comment after ready" {
  _run_fn '{"structured_output":{"demo":"## 🎬 Demo\n\nRun `foo --bar`."}}'
  [ "$status" -eq 0 ]
  # Two PR comments went out: the ready one (--body) and the demo one
  # (--body-file demo-comment.md).
  [ "$(grep -c '^gh pr comment' "$TRACE")" -eq 2 ]
  ready_line=$(grep -n '^gh pr comment.*Ready for review' "$TRACE" | head -1 | cut -d: -f1)
  demo_line=$(grep -n '^gh pr comment.*demo-comment.md' "$TRACE" | head -1 | cut -d: -f1)
  [ -n "$ready_line" ]
  [ -n "$demo_line" ]
  # Demo comment must come strictly AFTER the ready comment.
  [ "$demo_line" -gt "$ready_line" ]
  # And the rendered demo file holds the model's markdown verbatim.
  grep -q '🎬 Demo' "$WORK/demo-comment.md"
}

@test "empty/garbage claude output is treated as no-demo (graceful)" {
  _run_fn 'not json at all'
  [ "$status" -eq 0 ]
  grep -q 'All tasks complete. Ready for review.' "$TRACE"
  # Garbage parses to no demo → only the single ready comment, no demo comment.
  [ "$(grep -c '^gh pr comment' "$TRACE")" -eq 1 ]
}
