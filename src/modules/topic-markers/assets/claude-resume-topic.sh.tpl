#!/usr/bin/env bash
# claude-resume-topic.sh — Find a past Claude session by its $topic marker and resume it.
#
# The topic-markers hook writes a "($topic: … | $pct: … | $q: …)" line at the end of
# every assistant turn. Those lines live in the session transcripts under
# ~/.claude/projects/<cwd-slug>/<uuid>.jsonl. This command greps those markers,
# ranks sessions by how dominant the matched topic is, lets you pick when ambiguous,
# then runs `claude --resume <uuid>` from the session's original working directory
# (so Claude's cwd-scoped project store actually finds the session).
#
# Usage:
#   crt <query…>        Fuzzy-match the topic; resume best match (picker if ambiguous)
#   crt                 Interactive picker over every session that carries a topic
#   crt -l|--list <q>   List matches with mtime/cwd, don't resume
#   crt -n|--dry-run <q>  Print the resolved cwd + `claude --resume` command, don't run it
#   crt -h|--help
#
# Examples:
#   crt issue project sync
#   crt -l auto-dev

set -euo pipefail

PROJECTS_DIR="$HOME/.claude/projects"
CLAUDE_BIN={{scripts_dir}}/claude-stable
[[ -x "$CLAUDE_BIN" ]] || CLAUDE_BIN={{claude}}

die() { printf 'crt: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
  exit "${1:-0}"
}

MODE=resume
QUERY=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    -l|--list)    MODE=list ;;
    -n|--dry-run) MODE=dry ;;
    --)           shift; QUERY+=("$@"); break ;;
    -*)           die "unknown option: $1 (try --help)" ;;
    *)            QUERY+=("$1") ;;
  esac
  shift
done

[[ -d "$PROJECTS_DIR" ]] || die "no sessions dir at $PROJECTS_DIR"

# The session's working directory. Read it straight from the transcript — every
# JSONL record carries a "cwd" field, which is lossless. (The project *dir* name
# is a '/'→'-' slug of the cwd, but that's ambiguous when a real path component
# contains '-', e.g. "claude-toolkit", so we only fall back to de-slugging it.)
session_cwd() {
  local f="$1" cwd
  cwd=$(grep -om1 '"cwd":"[^"]*"' "$f" 2>/dev/null | sed 's/^"cwd":"//; s/"$//')
  if [[ -n "$cwd" ]]; then
    printf '%s\n' "$cwd"
  else
    printf '/%s\n' "$(basename "$(dirname "$f")" | sed 's/^-//; s/-/\//g')"
  fi
}

# Extract the last $topic marker text from a transcript (the session's settled topic).
last_topic() {
  grep -ohE '\(\$topic: [^|)]*' "$1" 2>/dev/null \
    | sed 's/^(\$topic: //; s/[[:space:]]*$//' \
    | tail -1
}

QUERY_WORDS=("${QUERY[@]:-}")

# Does the session's settled topic contain every query word? (case-insensitive,
# each word matched independently so word order / separators like → don't matter).
topic_matches() {
  local topic="$1" w
  for w in "${QUERY_WORDS[@]}"; do
    [[ -z "$w" ]] && continue
    grep -qiF -- "$w" <<<"$topic" || return 1
  done
  return 0
}

# Build a candidate table: <mtime_epoch>\t<uuid>\t<cwd>\t<score>\t<topic>
# We match against the session's *settled* (last) topic so a session is ranked by
# what it ended up being about, not by a topic it merely passed through. score =
# how many marker lines carry that exact settled topic → its dominance in the
# session, used only to break ties.
build_rows() {
  local f uuid cwd topic score
  while IFS= read -r f; do
    topic=$(last_topic "$f")
    [[ -z "$topic" ]] && continue
    if [[ ${#QUERY_WORDS[@]} -gt 0 && -n "${QUERY_WORDS[0]}" ]]; then
      topic_matches "$topic" || continue
    fi
    # Dominance: count marker lines whose topic equals the settled one.
    score=$(grep -cF -- "(\$topic: $topic" "$f" 2>/dev/null || true)
    uuid=$(basename "$f" .jsonl)
    cwd=$(session_cwd "$f")
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$(date -r "$f" '+%s' 2>/dev/null || echo 0)" "$uuid" "$cwd" "${score:-1}" "$topic"
  done < <(grep -rlE '\(\$topic:' "$PROJECTS_DIR" 2>/dev/null)
}

ROWS=$(build_rows | sort -t$'\t' -k4,4nr -k1,1nr)
[[ -n "$ROWS" ]] || die "no session matches topic: ${QUERY_WORDS[*]:-<any>}"

# Human-friendly one-liner per row for listing / picking.
fmt() {
  while IFS=$'\t' read -r epoch uuid cwd score topic; do
    printf '%s  [%s]  %s  (%s)  %s\n' \
      "$(date -r "$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" \
      "$score" "${uuid:0:8}" "$(basename "$cwd")" "$topic"
  done
}

if [[ "$MODE" == list ]]; then
  printf '%s\n' "$ROWS" | fmt
  exit 0
fi

# Choose the row to resume.
pick_row() {
  local n; n=$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')
  if [[ "$n" -eq 1 ]]; then
    printf '%s\n' "$ROWS"; return
  fi
  if command -v fzf >/dev/null 2>&1; then
    # Pair each fzf line with its raw row via a trailing tab + index trick.
    local sel
    sel=$(paste -d'\t' <(printf '%s\n' "$ROWS" | fmt) <(printf '%s\n' "$ROWS") \
      | fzf --with-nth=1 --delimiter='\t' --prompt='resume › ' --height=40% --reverse) || exit 130
    # The raw row is everything after the formatted prefix (last 5 tab-fields).
    printf '%s\n' "$sel" | awk -F'\t' '{print $(NF-4)"\t"$(NF-3)"\t"$(NF-2)"\t"$(NF-1)"\t"$NF}'
  else
    # No fzf: take the top-ranked row but tell the user what else matched.
    printf 'Multiple matches (install fzf to pick). Using the top one:\n' >&2
    printf '%s\n' "$ROWS" | fmt | sed 's/^/  /' >&2
    printf '%s\n' "$ROWS" | head -1
  fi
}

IFS=$'\t' read -r _epoch UUID CWD _score TOPIC < <(pick_row)
[[ -n "${UUID:-}" ]] || die "no selection"

if [[ "$MODE" == dry ]]; then
  printf 'topic : %s\n' "$TOPIC"
  printf 'cwd   : %s\n' "$CWD"
  printf 'cmd   : (cd %q && %q --resume %s)\n' "$CWD" "$CLAUDE_BIN" "$UUID"
  exit 0
fi

[[ -d "$CWD" ]] || die "session cwd no longer exists: $CWD"
cd "$CWD"
exec "$CLAUDE_BIN" --resume "$UUID"
