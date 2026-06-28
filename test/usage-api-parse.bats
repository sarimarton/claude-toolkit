#!/usr/bin/env bats
# Tests for the OAuth /api/oauth/usage → menubar-schema transform.
#
# The transform is a pure stdin(JSON)→stdout(JSON) Python block embedded in
# claude-usage-poll.sh.tpl. We extract it to a standalone runner once and feed
# it real API-shaped fixtures, asserting the downstream contract the menubar
# plugin (claude.10s.sh.tpl) reads: pct / reset_ts / weekly_pct /
# weekly_reset_ts / last_success_ts / rate_limited / ts.

setup() {
  TPL="${BATS_TEST_DIRNAME}/../src/modules/usage-monitor/assets/claude-usage-poll.sh.tpl"
  RUNNER="${BATS_TEST_TMPDIR}/api_parse.py"
  # Extract the API-parse block: everything between the markers.
  awk '/# >>> API_PARSE_BEGIN/{f=1;next} /# <<< API_PARSE_END/{f=0} f' "$TPL" > "$RUNNER"
  [ -s "$RUNNER" ] || { echo "API_PARSE block missing — extraction markers removed?"; return 1; }
}

# A normal active session: 6% used, weekly 2%, both with ISO reset timestamps.
@test "parses session + weekly pct and reset timestamps" {
  cat > "${BATS_TEST_TMPDIR}/fix.json" <<'JSON'
{"five_hour":{"utilization":6.0,"resets_at":"2099-06-28T03:50:00.301260+00:00"},
 "seven_day":{"utilization":2.0,"resets_at":"2099-07-04T11:00:00.301278+00:00"}}
JSON
  run bash -c "POLL_PHASES='[\"api\"]' python3 '$RUNNER' < '${BATS_TEST_TMPDIR}/fix.json'"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["pct"]==6, d
assert d["weekly_pct"]==2, d
assert isinstance(d["reset_ts"],int) and d["reset_ts"]>0, d
assert isinstance(d["weekly_reset_ts"],int) and d["weekly_reset_ts"]>0, d
assert d["last_success_ts"]==d["ts"], d
assert "error" not in d, d
'
}

# Rounding: utilization arrives as a float; pct must be an int and clamp to 100.
@test "rounds float utilization and clamps to 100" {
  cat > "${BATS_TEST_TMPDIR}/fix.json" <<'JSON'
{"five_hour":{"utilization":101.4,"resets_at":"2099-06-28T03:50:00+00:00"},
 "seven_day":{"utilization":49.6,"resets_at":"2099-07-04T11:00:00+00:00"}}
JSON
  run bash -c "POLL_PHASES='[\"api\"]' python3 '$RUNNER' < '${BATS_TEST_TMPDIR}/fix.json'"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["pct"]==100, d           # clamped
assert d["weekly_pct"]==50, d     # rounded 49.6 -> 50
assert d.get("rate_limited") is True, d
'
}

# Missing reset (resets_at null) must not crash; pct still emitted.
@test "tolerates null resets_at" {
  cat > "${BATS_TEST_TMPDIR}/fix.json" <<'JSON'
{"five_hour":{"utilization":12.0,"resets_at":null},
 "seven_day":{"utilization":3.0,"resets_at":null}}
JSON
  run bash -c "POLL_PHASES='[\"api\"]' python3 '$RUNNER' < '${BATS_TEST_TMPDIR}/fix.json'"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["pct"]==12, d
assert "reset_ts" not in d, d
assert d["last_success_ts"]==d["ts"], d
'
}

# Malformed input → error key, no crash, no fake pct.
@test "malformed JSON yields error not crash" {
  run bash -c "POLL_PHASES='[\"api\"]' python3 '$RUNNER' <<< 'not json'"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert "pct" not in d, d
assert d.get("error"), d
'
}
