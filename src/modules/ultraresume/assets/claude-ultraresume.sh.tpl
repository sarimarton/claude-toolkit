#!/usr/bin/env bash
# claude-ultraresume.sh — the external (non-slash-command) half of /ultraresume.
#
# Resolve a prior Claude session and resume it with `claude --resume`, running
# from the session's own cwd so Claude's cwd-scoped project store finds it.
#
# Two ways to name the session:
#   claude-ultraresume.sh                 In a tmux pane: read the PRIOR session's
#                                         $topic from this pane's scrollback (the
#                                         same magic /ultraresume uses), excluding
#                                         the current session.
#   claude-ultraresume.sh <topic words…> Match a session whose settled $topic
#                                         contains all the given words (handy
#                                         outside tmux, or to override scrollback).
#
# Options:
#   -n, --dry-run   Print the resolved topic / cwd / command, don't launch.
#   -h, --help
#
# Installed on PATH as `claude-ultraresume`.

set -euo pipefail

PROJECTS="{{home}}/.claude/projects"
TMUX_BIN={{tmux}}
CLAUDE_BIN={{scripts_dir}}/claude-stable
[[ -x "$CLAUDE_BIN" ]] || CLAUDE_BIN={{claude}}

# shellcheck source=/dev/null
source "{{scripts_dir}}/ultraresume-lib.sh"

die() { printf 'claude-ultraresume: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit "${1:-0}"; }

DRY=false
QUERY_WORDS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    -n|--dry-run) DRY=true ;;
    --)           shift; QUERY_WORDS+=("$@"); break ;;
    -*)           die "unknown option: $1 (try --help)" ;;
    *)            QUERY_WORDS+=("$1") ;;
  esac
  shift
done

# Determine cwd + slug. In a pane we trust the pane's cwd; otherwise $PWD.
if [[ -n "${TMUX_PANE:-}" ]] && command -v "$TMUX_BIN" >/dev/null 2>&1; then
  cwd=$(TMUX= "$TMUX_BIN" display-message -t "$TMUX_PANE" -p '#{pane_current_path}' 2>/dev/null)
fi
cwd="${cwd:-$PWD}"
slug=$(ur_cwd_slug "$cwd")

self=$(ur_self_uuid "$PROJECTS" "$slug" || true)

# Build the query + pick the match mode. Explicit words → word-contains match
# (tolerates the em-dash and gaps in a hand-typed query). Scrollback → exact match
# (the query is a verbatim marker topic).
if [[ ${#QUERY_WORDS[@]} -gt 0 ]]; then
  query="${QUERY_WORDS[*]}"
  uuid=$(ur_resolve_uuid_words "$PROJECTS" "$slug" "$query" "$self") \
    || die "no prior session whose topic contains: $query"
elif [[ -n "${TMUX_PANE:-}" ]] && command -v "$TMUX_BIN" >/dev/null 2>&1; then
  self_topic=""
  [[ -n "$self" ]] && self_topic=$(ur_last_topic "$PROJECTS/$slug/$self.jsonl" || true)
  scrollback=$(TMUX= "$TMUX_BIN" capture-pane -t "$TMUX_PANE" -p -S -3000 -J 2>/dev/null) \
    || die "could not capture scrollback"
  query=$(ur_scrollback_topic "$scrollback" "$self_topic") \
    || die "no prior \$topic marker in scrollback (pass topic words explicitly)"
  uuid=$(ur_resolve_uuid "$PROJECTS" "$slug" "$query" "$self") \
    || die "no prior session matches topic: $query"
else
  die "not in a tmux pane — pass topic words, e.g. claude-ultraresume fin menü RCA"
fi

# The session's real cwd (lossless, from the transcript's "cwd" field) so we
# resume from where it ran — the slug is lossy and can't be reversed reliably.
session_cwd=$(grep -aom1 '"cwd":"[^"]*"' "$PROJECTS/$slug/$uuid.jsonl" 2>/dev/null \
  | sed 's/^"cwd":"//; s/"$//')
session_cwd="${session_cwd:-$cwd}"

if $DRY; then
  printf 'topic : %s\n' "$query"
  printf 'uuid  : %s\n' "$uuid"
  printf 'cwd   : %s\n' "$session_cwd"
  printf 'cmd   : (cd %q && %q --resume %s)\n' "$session_cwd" "$CLAUDE_BIN" "$uuid"
  exit 0
fi

[[ -d "$session_cwd" ]] || die "session cwd no longer exists: $session_cwd"
cd "$session_cwd"
exec "$CLAUDE_BIN" --resume "$uuid"
