#!/usr/bin/env bats
# ultraresume-lib: the pure-logic core of /ultraresume.
#
# Two unit-testable functions live here (everything tmux/claude-touching is in the
# thin entrypoints, manually verified):
#
#   ur_marker_topic   <line>   — extract the topic text from ONE marker line, i.e.
#                                everything between "($topic:" and the first "|"
#                                (or ")"), trimmed. Rejects the hook-instruction
#                                TEMPLATE line ("<téma 5-10 …>") so it never leaks
#                                into a query. Anchors ONLY on "($topic:" + first
#                                "|" — never on $pct vs $completeness vs $q (two
#                                marker generations coexist in old transcripts).
#
#   ur_scrollback_topic <text> [self-topic]
#                              — given a pane's captured scrollback, return the
#                                PRIOR session's topic: the last "($topic: …)"
#                                marker whose topic is NOT the self-topic (the
#                                current session's settled topic, passed in by the
#                                caller from ur_self_uuid→ur_last_topic). Topic-text
#                                exclusion, not a fragile banner cut.

setup() {
  TESTDIR="$(mktemp -d)"
  TPL="$BATS_TEST_DIRNAME/../src/modules/ultraresume/assets/ultraresume-lib.sh.tpl"
  LIB="$TESTDIR/ultraresume-lib.sh"
  sed "s#{{home}}#$TESTDIR#g" "$TPL" > "$LIB"
  # The lib is a sourced library; load it so its functions are in scope.
  # shellcheck disable=SC1090
  source "$LIB"
}
teardown() { rm -rf "$TESTDIR"; }

# ─────────────────────────── ur_marker_topic ───────────────────────────

@test "marker_topic: extracts topic up to the first pipe (live \$pct/\$q marker)" {
  run ur_marker_topic '  ($topic: fin menü üres — finance scraper RCA | $pct: 30 | $q: o?)'
  [ "$status" -eq 0 ]
  [ "$output" = "fin menü üres — finance scraper RCA" ]
}

@test "marker_topic: handles the older \$completeness/\$state marker generation" {
  run ur_marker_topic '($topic: auto-dev címke sanitizálás | $completeness: 80 | $state: done)'
  [ "$status" -eq 0 ]
  [ "$output" = "auto-dev címke sanitizálás" ]
}

@test "marker_topic: rejects the hook-instruction template line" {
  run ur_marker_topic '($topic: <téma 5-10 szóban> | $pct: <0-100> | $q: <s|o|h><+|-|?>)'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "marker_topic: returns non-zero for a line with no marker" {
  run ur_marker_topic 'just some normal output line'
  [ "$status" -ne 0 ]
}

@test "marker_topic: trims surrounding whitespace from the topic" {
  run ur_marker_topic '($topic:    spaced out topic    | $pct: 50 | $q: s+)'
  [ "$status" -eq 0 ]
  [ "$output" = "spaced out topic" ]
}

# ───────────────────────── ur_scrollback_topic ─────────────────────────

# A realistic two-session scrollback: an OLD finished session, then the CURRENT
# session whose settled topic (passed as self-topic) must be excluded.
mk_scrollback() {
  cat <<'EOF'
── #10 02:10:03  ~/.config ──────────
~/.config (main) $ c
 ▐▛███▜▌   Claude Code v2.1.170
❯ üres a "fin" menü. ultracode
  ($topic: fin menü üres — finance scraper RCA | $pct: 30 | $q: o?)
── #16 02:30:35  ~/.config ──────────
~/.config (main) $ c
 ▐▛███▜▌   Claude Code v2.1.176
❯ nézd meg ezt a tmux pane-t
  ($topic: scrollback-téma visszakeresése Claude sessionök közt | $pct: 100 | $q: o+)
❯ Köszönöm
  ($topic: scrollback-téma visszakeresése Claude sessionök közt | $pct: 100 | $q: o+)
EOF
}

@test "scrollback_topic: returns the PRIOR topic, excluding the self-topic" {
  run ur_scrollback_topic "$(mk_scrollback)" "scrollback-téma visszakeresése Claude sessionök közt"
  [ "$status" -eq 0 ]
  [ "$output" = "fin menü üres — finance scraper RCA" ]
}

@test "scrollback_topic: ignores the hook-instruction template line" {
  scrollback="$(printf '%s\n%s\n%s\n' \
    '($topic: <téma 5-10 szóban> | $pct: <0-100> | $q: <s|o|h>)' \
    '($topic: real prior topic | $pct: 90 | $q: o+)' \
    '($topic: current session topic | $pct: 10 | $q: o?)')"
  run ur_scrollback_topic "$scrollback" "current session topic"
  [ "$status" -eq 0 ]
  [ "$output" = "real prior topic" ]
}

@test "scrollback_topic: self-topic exclusion is case-insensitive and skips ALL its repeats" {
  # The self topic recurs many times (every turn emits a marker); every occurrence
  # must be skipped, leaving the nearest genuinely-different prior topic.
  scrollback="$(printf '%s\n%s\n%s\n%s\n' \
    '($topic: fin menü üres — finance scraper RCA | $pct: 30 | $q: o?)' \
    '($topic: Current Session Topic | $pct: 50 | $q: o+)' \
    '($topic: current session topic | $pct: 80 | $q: o+)' \
    '($topic: current session topic | $pct: 100 | $q: o+)')"
  run ur_scrollback_topic "$scrollback" "current session topic"
  [ "$status" -eq 0 ]
  [ "$output" = "fin menü üres — finance scraper RCA" ]
}

@test "scrollback_topic: fails cleanly when only the self-topic is present" {
  scrollback="$(printf '%s\n%s\n' \
    '($topic: only the current session | $pct: 10 | $q: o?)' \
    '($topic: only the current session | $pct: 40 | $q: o+)')"
  run ur_scrollback_topic "$scrollback" "only the current session"
  [ "$status" -ne 0 ]
}

@test "scrollback_topic: with no self-topic given, takes the last marker overall" {
  scrollback="$(printf '%s\n%s\n' \
    '($topic: earlier topic | $pct: 40 | $q: o+)' \
    '($topic: later topic | $pct: 80 | $q: o+)')"
  run ur_scrollback_topic "$scrollback"
  [ "$status" -eq 0 ]
  [ "$output" = "later topic" ]
}

# ────────────────────────── ur_resolve_uuid ──────────────────────────
#
# ur_resolve_uuid <projects-dir> <slug> <query-topic> <self-uuid>
#   Glob the cwd-scoped project dir (top-level *.jsonl only — never the
#   subagents/ subtree), rank transcripts whose EMITTED settled topic matches the
#   query, EXCLUDE the self-uuid, and print the winning UUID. mtime breaks ties.

# Write a fake transcript carrying $n emitted markers of $topic, with an explicit
# mtime so ranking is deterministic. Args: dir uuid topic n mtime(YYYYMMDDhhmm)
mk_session() {
  local dir="$1" uuid="$2" topic="$3" n="$4" mtime="$5" f i
  f="$dir/$uuid.jsonl"
  : > "$f"
  printf '{"type":"user","message":{"content":"start"},"cwd":"/Users/sarim/.config"}\n' >> "$f"
  for ((i=0; i<n; i++)); do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"blah ($topic: %s | $pct: 50 | $q: o+)"}]}}\n' "$topic" >> "$f"
  done
  touch -t "$mtime" "$f"
}

setup_projects() {
  PROJ="$TESTDIR/projects"
  SLUG="-Users-sarim--config"
  mkdir -p "$PROJ/$SLUG/subagents"
}

@test "resolve_uuid: returns the session whose settled topic matches the query" {
  setup_projects
  mk_session "$PROJ/$SLUG" "aaaaaaaa-0000-0000-0000-000000000001" "fin menü üres — finance scraper RCA" 2 202606130600
  mk_session "$PROJ/$SLUG" "bbbbbbbb-0000-0000-0000-000000000002" "valami egészen más téma" 3 202606130700
  run ur_resolve_uuid "$PROJ" "$SLUG" "fin menü üres — finance scraper RCA" "zzzzzzzz-self"
  [ "$status" -eq 0 ]
  [ "$output" = "aaaaaaaa-0000-0000-0000-000000000001" ]
}

@test "resolve_uuid: EXCLUDES the current (self) session even if it matches" {
  setup_projects
  # The self session matches AND is newer — must still be excluded.
  mk_session "$PROJ/$SLUG" "dcabbadb-0000-0000-0000-00000000self" "fin menü üres — finance scraper RCA" 6 202606130837
  mk_session "$PROJ/$SLUG" "c9363c58-0000-0000-0000-0000000prior" "fin menü üres — finance scraper RCA" 2 202606130613
  run ur_resolve_uuid "$PROJ" "$SLUG" "fin menü üres — finance scraper RCA" "dcabbadb-0000-0000-0000-00000000self"
  [ "$status" -eq 0 ]
  [ "$output" = "c9363c58-0000-0000-0000-0000000prior" ]
}

@test "resolve_uuid: mtime breaks ties between two matching prior sessions" {
  setup_projects
  mk_session "$PROJ/$SLUG" "older000-0000-0000-0000-00000000000a" "közös téma" 2 202606130500
  mk_session "$PROJ/$SLUG" "newer000-0000-0000-0000-00000000000b" "közös téma" 2 202606130800
  run ur_resolve_uuid "$PROJ" "$SLUG" "közös téma" "zzzzzzzz-self"
  [ "$status" -eq 0 ]
  [ "$output" = "newer000-0000-0000-0000-00000000000b" ]
}

@test "resolve_uuid: never descends into the subagents/ subtree" {
  setup_projects
  # A decoy subagent transcript with a matching marker must be ignored.
  mk_session "$PROJ/$SLUG/subagents" "agent-decoy-0000-0000-0000-0000dec" "fin menü üres — finance scraper RCA" 9 202606130900
  mk_session "$PROJ/$SLUG" "real0000-0000-0000-0000-00000000real" "fin menü üres — finance scraper RCA" 1 202606130100
  run ur_resolve_uuid "$PROJ" "$SLUG" "fin menü üres — finance scraper RCA" "zzzzzzzz-self"
  [ "$status" -eq 0 ]
  [ "$output" = "real0000-0000-0000-0000-00000000real" ]
}

@test "resolve_uuid: fails (non-zero) when nothing but the self session matches" {
  setup_projects
  mk_session "$PROJ/$SLUG" "onlyself-0000-0000-0000-00000000self" "magányos téma" 3 202606130800
  run ur_resolve_uuid "$PROJ" "$SLUG" "magányos téma" "onlyself-0000-0000-0000-00000000self"
  [ "$status" -ne 0 ]
}

# ──────────────────── ur_resolve_uuid_words ────────────────────
#
# Word-mode resolution for the EXTERNAL entrypoint's explicit query (crt-style):
# match when the session's settled topic contains EVERY query word (case-
# insensitive, order-independent). Same scoping/self-exclusion/mtime-tiebreak as
# ur_resolve_uuid. Used so `claude-ultraresume fin menü RCA` matches a topic like
# "fin menü üres — finance scraper RCA" despite the em-dash and word gaps.

@test "resolve_uuid_words: matches when all words appear in the settled topic" {
  setup_projects
  mk_session "$PROJ/$SLUG" "wmatch00-0000-0000-0000-0000000000w1" "fin menü üres — finance scraper RCA" 2 202606130600
  mk_session "$PROJ/$SLUG" "wother00-0000-0000-0000-0000000000w2" "valami más" 2 202606130700
  run ur_resolve_uuid_words "$PROJ" "$SLUG" "fin menü RCA" "zzzzzzzz-self"
  [ "$status" -eq 0 ]
  [ "$output" = "wmatch00-0000-0000-0000-0000000000w1" ]
}

@test "resolve_uuid_words: requires ALL words (a missing word disqualifies)" {
  setup_projects
  mk_session "$PROJ/$SLUG" "wpart000-0000-0000-0000-0000000000w3" "fin menü üres" 2 202606130600
  run ur_resolve_uuid_words "$PROJ" "$SLUG" "fin menü hiányzószó" "zzzzzzzz-self"
  [ "$status" -ne 0 ]
}

@test "resolve_uuid_words: excludes the self session" {
  setup_projects
  mk_session "$PROJ/$SLUG" "wself000-0000-0000-0000-0000000self" "fin menü üres — finance scraper RCA" 5 202606130900
  mk_session "$PROJ/$SLUG" "wprior00-0000-0000-0000-000000prior" "fin menü üres — finance scraper RCA" 2 202606130600
  run ur_resolve_uuid_words "$PROJ" "$SLUG" "fin menü" "wself000-0000-0000-0000-0000000self"
  [ "$status" -eq 0 ]
  [ "$output" = "wprior00-0000-0000-0000-000000prior" ]
}

# ──────────────────── full chain (integration) ────────────────────
#
# Exercises the exact sequence both entrypoints run:
#   ur_self_uuid → ur_last_topic → ur_scrollback_topic → ur_resolve_uuid
# against fixture transcripts + a clean scrollback, proving the PRIOR session is
# resolved and the CURRENT one excluded. (The two filesystem-touching helpers,
# ur_self_uuid/ur_last_topic, are covered here rather than in isolation.)

@test "full chain: scrollback → prior session UUID, current session excluded" {
  setup_projects
  # Current session: newest mtime, settled topic "ultraresume modul fejlesztés".
  mk_session "$PROJ/$SLUG" "dcabbadb-aaaa-bbbb-cccc-000000000002" "ultraresume modul fejlesztés" 3 202606130837
  # Prior session: older, the one we want back.
  mk_session "$PROJ/$SLUG" "c9363c58-aaaa-bbbb-cccc-000000000001" "fin menü üres — finance scraper RCA" 2 202606130613

  scrollback="$(printf '%s\n%s\n%s\n' \
    '($topic: fin menü üres — finance scraper RCA | $pct: 30 | $q: o?)' \
    '($topic: ultraresume modul fejlesztés | $pct: 40 | $q: o+)' \
    '($topic: ultraresume modul fejlesztés | $pct: 60 | $q: o+)')"

  self=$(ur_self_uuid "$PROJ" "$SLUG")
  [ "$self" = "dcabbadb-aaaa-bbbb-cccc-000000000002" ]

  self_topic=$(ur_last_topic "$PROJ/$SLUG/$self.jsonl")
  [ "$self_topic" = "ultraresume modul fejlesztés" ]

  query=$(ur_scrollback_topic "$scrollback" "$self_topic")
  [ "$query" = "fin menü üres — finance scraper RCA" ]

  run ur_resolve_uuid "$PROJ" "$SLUG" "$query" "$self"
  [ "$status" -eq 0 ]
  [ "$output" = "c9363c58-aaaa-bbbb-cccc-000000000001" ]
}
