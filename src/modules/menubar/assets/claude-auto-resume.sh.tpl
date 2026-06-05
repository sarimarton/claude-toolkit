#!/usr/bin/env bash
# claude-auto-resume.sh — Auto-resume every dead Claude pane in ONE tmux session.
#
# WHY: after a reboot, tmux-continuum restores the "✻ topic" windows (name +
# scrollback + original cwd) but the Claude process inside each is gone — the pane
# runs a plain shell. The menu offers a manual ○ "Resume" per pane, but the user
# wants the panes they actually open to come back on their own. This script is the
# automatic counterpart: fired from tmux's `client-attached` hook (see tmux.conf),
# it walks the just-attached session's topic windows and resumes each dead one.
#
# It reuses claude-resume.sh --no-attach for the actual relaunch (the attaching
# client is already on screen, so no extra terminal tab is opened) and the same
# resume-index + surviving-.jsonl logic the menu uses, so behavior stays in sync.
#
# Usage: claude-auto-resume.sh <session_name>
#   <session_name> — the tmux session a client just attached to (#{session_name}).

SESSION="$1"
[[ -z "$SESSION" ]] && exit 0
[[ "$SESSION" == "claude_usage_mon" ]] && exit 0

TMUX_BIN={{tmux}}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESUME_INDEX="{{state_dir}}/resume-index.tsv"
PROJ_ROOT="$HOME/.claude/projects"

[[ -f "$RESUME_INDEX" ]] || exit 0

# One pass per topic window in this session. Mirrors the menu's dead-detector
# (claude.10s.sh): skip alive panes (command looks like a version string N.N.N),
# only "✻ " topic windows, dedup by window_id, and resolve the newest UUID whose
# .jsonl still exists on disk — skipping windows with no recoverable session.
seen_windows=""
while IFS=$'\t' read -r win_name proc pane_id window_id; do
    [[ "$proc" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue   # Claude already alive here
    case "$win_name" in "✻ "*) ;; *) continue ;; esac        # only topic windows
    case "$seen_windows" in *"|$window_id|"*) continue ;; esac
    seen_windows="${seen_windows}|${window_id}|"

    # Newest surviving UUID for this (session, window-name). Rows are oldest-first,
    # so the last survivor found wins (matches the menu's selection).
    uuid=""
    while IFS= read -r cand; do
        [[ -z "$cand" ]] && continue
        if compgen -G "$PROJ_ROOT"/*/"$cand".jsonl >/dev/null 2>&1; then
            uuid="$cand"
        fi
    done < <(awk -F'\t' -v s="$SESSION" -v w="$win_name" '$1==s && $2==w {print $3}' "$RESUME_INDEX")
    [[ -z "$uuid" ]] && continue   # nothing recoverable → leave the shell as-is

    # Relaunch in-pane, no terminal tab (the client is already attached). Detached
    # so a slow Claude start doesn't stall the client-attached hook.
    "$SCRIPT_DIR/claude-resume.sh" --no-attach "$SESSION" "$pane_id" "$uuid" >/dev/null 2>&1 &
done < <(TMUX= $TMUX_BIN list-panes -t "$SESSION" \
    -F "#{window_name}	#{pane_current_command}	#{pane_id}	#{window_id}" 2>/dev/null)

exit 0
