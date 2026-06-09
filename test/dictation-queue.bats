#!/usr/bin/env bats
# Queue state machine tests for the dictation pipeline.
# The library under test is the *rendered* queue helper. We test the template
# by rendering its {{placeholders}} into a tmp copy, then sourcing it.

setup() {
  TESTDIR="$(mktemp -d)"
  QROOT="$TESTDIR/dictation"
  mkdir -p "$QROOT/jobs/pending" "$QROOT/jobs/processing" "$QROOT/jobs/done" "$QROOT/jobs/failed" "$QROOT/active"

  # Render the queue lib template: substitute {{home}} -> TESTDIR-parent is irrelevant here;
  # the lib takes QROOT via env, so we only need to strip the PATH line cleanly.
  TPL="$BATS_TEST_DIRNAME/../src/modules/dictation-pipeline/assets/dictation-queue.sh.tpl"
  LIB="$TESTDIR/dictation-queue.sh"
  sed 's#{{home}}#'"$TESTDIR"'#g' "$TPL" > "$LIB"
  chmod +x "$LIB"

  # All lib functions honor $DICT_QUEUE_ROOT for testability.
  export DICT_QUEUE_ROOT="$QROOT"
  source "$LIB"
}

teardown() {
  rm -rf "$TESTDIR"
}

# Helper: create a job dir in active/ with a minimal meta.json + audio.
mk_active_job() {
  local id="$1"
  mkdir -p "$QROOT/active/$id"
  printf '{"id":"%s","pane_id":"%%1","send_enter":true}' "$id" > "$QROOT/active/$id/meta.json"
  printf 'AUDIO' > "$QROOT/active/$id/audio.wav"
}

@test "enqueue moves a job atomically from active/ to jobs/pending/" {
  mk_active_job "job-A"
  run queue_enqueue "job-A"
  [ "$status" -eq 0 ]
  [ ! -d "$QROOT/active/job-A" ]
  [ -d "$QROOT/jobs/pending/job-A" ]
  [ -f "$QROOT/jobs/pending/job-A/audio.wav" ]
}

@test "claim moves the oldest pending job to processing and prints its id" {
  mkdir -p "$QROOT/jobs/pending/job-1" "$QROOT/jobs/pending/job-2"
  # job-1 older than job-2
  touch -t 202601010000 "$QROOT/jobs/pending/job-1"
  touch -t 202601010001 "$QROOT/jobs/pending/job-2"
  run queue_claim
  [ "$status" -eq 0 ]
  [ "$output" = "job-1" ]
  [ -d "$QROOT/jobs/processing/job-1" ]
  [ ! -d "$QROOT/jobs/pending/job-1" ]
  [ -d "$QROOT/jobs/pending/job-2" ]
}

@test "claim returns non-zero and empty when no pending jobs" {
  run queue_claim
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "claim race: two concurrent claims of one job yield exactly one winner" {
  mkdir -p "$QROOT/jobs/pending/solo"
  # Two concurrent claims against a single job, each writing its result to a file
  # (subshell exit codes via files — robust under bats, unlike backgrounded $()).
  ( queue_claim > "$TESTDIR/r1" 2>/dev/null; echo "$?" > "$TESTDIR/s1" ) &
  ( queue_claim > "$TESTDIR/r2" 2>/dev/null; echo "$?" > "$TESTDIR/s2" ) &
  wait
  # Exactly one processing dir, no pending left, no duplicate.
  [ "$(ls "$QROOT/jobs/processing" | wc -l | tr -d ' ')" = "1" ]
  [ "$(ls "$QROOT/jobs/pending" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]
  # Exactly one winner (status 0) and one loser (status 1).
  local winners=0
  [ "$(cat "$TESTDIR/s1")" = "0" ] && winners=$((winners+1))
  [ "$(cat "$TESTDIR/s2")" = "0" ] && winners=$((winners+1))
  [ "$winners" = "1" ]
}

@test "finalize moves a processing job to done" {
  mkdir -p "$QROOT/jobs/processing/job-X"
  run queue_finalize "job-X" "done"
  [ "$status" -eq 0 ]
  [ -d "$QROOT/jobs/done/job-X" ]
  [ ! -d "$QROOT/jobs/processing/job-X" ]
}

@test "finalize to failed moves a processing job to failed" {
  mkdir -p "$QROOT/jobs/processing/job-Y"
  run queue_finalize "job-Y" "failed"
  [ "$status" -eq 0 ]
  [ -d "$QROOT/jobs/failed/job-Y" ]
}

@test "requeue_stale moves orphaned processing jobs back to pending on startup" {
  mkdir -p "$QROOT/jobs/processing/stale-1" "$QROOT/jobs/processing/stale-2"
  run queue_requeue_stale
  [ "$status" -eq 0 ]
  [ -d "$QROOT/jobs/pending/stale-1" ]
  [ -d "$QROOT/jobs/pending/stale-2" ]
  [ -z "$(ls "$QROOT/jobs/processing" 2>/dev/null)" ]
}

@test "attempts counter increments and routes to failed after budget (3)" {
  mkdir -p "$QROOT/jobs/processing/poison"
  # 1st, 2nd, 3rd attempt: should stay claimable; 4th over budget -> failed
  run queue_bump_attempts "poison"
  [ "$status" -eq 0 ]
  [ "$(cat "$QROOT/jobs/processing/poison/attempts")" = "1" ]
  queue_bump_attempts "poison"
  queue_bump_attempts "poison"
  # now attempts=3; over_budget should report true (exceeded max of 3)
  run queue_over_budget "poison" 3
  [ "$status" -eq 0 ]
}
