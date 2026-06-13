#!/usr/bin/env bash
# ultraresume-lib.sh — pure-logic core shared by the in-pane and external
# /ultraresume entrypoints. Sourced, not executed. No tmux/claude side effects
# live here, so this file is the unit-tested surface (test/ultraresume-lib.bats).
#
# The "$topic" marker is written by the topic-markers hook at the end of every
# assistant turn as "($topic: … | $pct: … | $q: …)". Older transcripts carry a
# "($topic: … | $completeness: … | $state: …)" generation. Both are handled by
# anchoring ONLY on the "($topic:" literal and the first "|" (or ")") — never on
# the second field's key.

# ur_marker_topic <line>
# Extract the topic from a single marker line: the text between "($topic:" and the
# first "|" or ")", trimmed. Rejects the hook-instruction TEMPLATE so the literal
# placeholder ("<téma 5-10 …>") can never become a query. Exit 1 if no real topic.
ur_marker_topic() {
  local line="$1" topic
  # Must contain the literal marker prefix.
  [[ "$line" == *'($topic:'* ]] || return 1
  # Strip everything up to and including "($topic:", then cut at the first
  # field separator ("|") or the closing ")".
  topic="${line#*'($topic:'}"
  topic="${topic%%|*}"
  topic="${topic%%)*}"
  # Trim leading/trailing whitespace.
  topic="${topic#"${topic%%[![:space:]]*}"}"
  topic="${topic%"${topic##*[![:space:]]}"}"
  [[ -n "$topic" ]] || return 1
  # Reject the instruction template: a literal "<…>" placeholder is never a real
  # topic. The template's value starts with "<" (e.g. "<téma 5-10 szóban>").
  [[ "$topic" == '<'* ]] && return 1
  printf '%s\n' "$topic"
}

# ur_scrollback_topic <scrollback-text> [self-topic]
# Return the PRIOR session's topic from a pane's captured scrollback: the LAST
# valid "($topic:" marker whose topic is NOT the current session's settled topic.
#
# Self-exclusion is by TOPIC TEXT, not by a banner position. An earlier design
# cut the buffer at the most recent startup banner, but that is fragile: the
# scrollback can contain a verbatim copy of the banner/marker (e.g. while
# discussing sessions, or test fixtures echoed into the pane), so a textual
# look-alike gets mistaken for the real splash. The reliable signal is the self
# session's settled topic (the caller derives it from ur_self_uuid → ur_last_topic
# and passes it in). We skip markers equal to it; the newest remaining marker is
# the nearest prior topic. With no self-topic given, we take the last marker
# overall (single-session / non-Claude callers).
ur_scrollback_topic() {
  local scrollback="$1" self_topic="${2:-}" line topic last=""
  local self_lc; self_lc=$(printf '%s' "$self_topic" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r line; do
    topic=$(ur_marker_topic "$line") || continue
    if [[ -n "$self_lc" ]]; then
      [[ "$(printf '%s' "$topic" | tr '[:upper:]' '[:lower:]')" == "$self_lc" ]] && continue
    fi
    last="$topic"
  done < <(printf '%s\n' "$scrollback")
  [[ -n "$last" ]] || return 1
  printf '%s\n' "$last"
}

# ur_cwd_slug <cwd>
# Derive the ~/.claude/projects slug from a working directory: every "/" and "."
# becomes "-" (so "/Users/sarim/.config" → "-Users-sarim--config", the double dash
# coming from the leading dot of ".config"). Lossy/non-invertible — only ever go
# cwd→slug, never the reverse.
ur_cwd_slug() {
  printf '%s\n' "$1" | sed 's/[/.]/-/g'
}

# ur_last_topic <jsonl-file>
# The session's SETTLED topic: the last emitted "($topic: …)" marker in file order.
# Pulls every "($topic: …)" occurrence out of the transcript (one per line) and
# runs each through ur_marker_topic, so the template line and marker-generation
# drift are rejected identically to the scrollback path. Mirrors crt's last_topic.
ur_last_topic() {
  local f="$1" occ topic last=""
  while IFS= read -r occ; do
    topic=$(ur_marker_topic "$occ") || continue
    last="$topic"
  done < <(grep -aoE '\(\$topic:[^)|]*[|)]' "$f" 2>/dev/null)
  [[ -n "$last" ]] || return 1
  printf '%s\n' "$last"
}

# _ur_rank <projects-dir> <slug> <self-uuid> <mode> <query>
# Internal: scan top-level "$projects/$slug/"*.jsonl (never the subagents/ subtree),
# exclude the self-uuid, keep transcripts whose SETTLED topic matches <query> under
# <mode>, and print the newest matching UUID (mtime tie-break). Exit 1 if none.
#   mode=exact  — settled topic equals query (case-insensitive). Used by the
#                 scrollback path, where the query IS a verbatim marker topic.
#   mode=words  — settled topic contains EVERY whitespace-separated query word
#                 (case-insensitive, order-independent). Used by the external
#                 entrypoint's hand-typed query.
_ur_rank() {
  local projects="$1" slug="$2" self="$3" mode="$4" query="$5"
  # NB: derive $dir on its OWN line — a single `local a=$1 b=$a` does NOT see the
  # just-assigned $a within the same `local` statement in bash, yielding dir="/".
  local dir="$projects/$slug"
  local f uuid topic topic_lc best="" best_mtime=0 mtime w ok
  local q_lc; q_lc=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')
  shopt -s nullglob
  for f in "$dir"/*.jsonl; do
    uuid=$(basename "$f" .jsonl)
    [[ "$uuid" == "$self" ]] && continue
    [[ "$uuid" == agent-* ]] && continue   # belt-and-braces; subagents live a level down
    topic=$(ur_last_topic "$f") || continue
    topic_lc=$(printf '%s' "$topic" | tr '[:upper:]' '[:lower:]')
    if [[ "$mode" == words ]]; then
      ok=1
      for w in $q_lc; do
        [[ "$topic_lc" == *"$w"* ]] || { ok=0; break; }
      done
      (( ok )) || continue
    else
      [[ "$topic_lc" == "$q_lc" ]] || continue
    fi
    mtime=$(stat -f '%m' "$f" 2>/dev/null || date -r "$f" '+%s' 2>/dev/null || echo 0)
    if (( mtime > best_mtime )); then
      best_mtime=$mtime
      best="$uuid"
    fi
  done
  shopt -u nullglob
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

# ur_resolve_uuid <projects-dir> <slug> <query-topic> <self-uuid>
# Best PRIOR session whose settled topic EQUALS the query (case-insensitive).
ur_resolve_uuid() {
  _ur_rank "$1" "$2" "$4" exact "$3"
}

# ur_resolve_uuid_words <projects-dir> <slug> <query-words> <self-uuid>
# Best PRIOR session whose settled topic CONTAINS every query word.
ur_resolve_uuid_words() {
  _ur_rank "$1" "$2" "$4" words "$3"
}

# ur_self_uuid <projects-dir> <slug>
# Best-effort identity of the CURRENT session's transcript, env-free: the newest
# top-level *.jsonl in the cwd-scoped project dir — the live `claude` engine just
# appended this turn to it. Used to exclude self from ur_resolve_uuid. Not unit
# tested (depends on live mtimes); the resolve_uuid self-exclusion IS tested with
# an explicit self argument.
ur_self_uuid() {
  local projects="$1" slug="$2"
  local dir="$projects/$slug" newest   # $dir on its own line (see ur_resolve_uuid)
  newest=$(ls -t "$dir"/*.jsonl 2>/dev/null | grep -v '/agent-' | head -1)
  [[ -n "$newest" ]] || return 1
  basename "$newest" .jsonl
}
