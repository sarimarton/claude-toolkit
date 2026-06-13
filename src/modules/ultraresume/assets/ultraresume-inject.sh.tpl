#!/usr/bin/env bash
# ultraresume-inject.sh — the in-pane half of /ultraresume.
#
# Runs from INSIDE a live Claude pane (invoked by the /ultraresume slash command).
# It reads the pane's scrollback, finds the PRIOR Claude session shown there by its
# "$topic" marker, resolves that session's transcript UUID, and SELF-INJECTS
# "/resume <uuid>" + Enter into this same pane's prompt — so Claude (already
# running) switches to that session.
#
# Why a slash command can't just call /resume: custom commands inject a prompt,
# not a TUI action. So we drive the prompt from the outside via tmux send-keys —
# exactly the primitive claude-resume.sh uses for reboot recovery.
#
# Usage: ultraresume-inject.sh <pane-id>
#   <pane-id> is the caller's "$TMUX_PANE" (e.g. "%23"). The slash command passes
#   it so we target THIS pane, never whichever pane happens to be active.

set -euo pipefail

PANE="${1:-${TMUX_PANE:-}}"
TMUX_BIN={{tmux}}
PROJECTS="{{home}}/.claude/projects"

# shellcheck source=/dev/null
source "{{scripts_dir}}/ultraresume-lib.sh"

die() { printf 'ultraresume: %s\n' "$*" >&2; exit 1; }

[[ -n "$PANE" ]] || die "no pane id (pass \$TMUX_PANE)"
command -v "$TMUX_BIN" >/dev/null 2>&1 || die "tmux not found at $TMUX_BIN"

# cwd of THIS pane → the project slug that scopes the session search.
cwd=$(TMUX= "$TMUX_BIN" display-message -t "$PANE" -p '#{pane_current_path}' 2>/dev/null)
[[ -n "$cwd" ]] || die "could not read pane cwd"
slug=$(ur_cwd_slug "$cwd")

# Identify (and later exclude) the current session: the newest top-level
# transcript in this cwd's project dir — the live engine just appended to it.
self=$(ur_self_uuid "$PROJECTS" "$slug" || true)
self_topic=""
[[ -n "$self" ]] && self_topic=$(ur_last_topic "$PROJECTS/$slug/$self.jsonl" || true)

# The PRIOR topic from scrollback (the self-topic is skipped). -J joins wrapped
# lines so a long marker isn't clipped mid-topic; -S -3000 looks well back.
scrollback=$(TMUX= "$TMUX_BIN" capture-pane -t "$PANE" -p -S -3000 -J 2>/dev/null) \
  || die "could not capture scrollback for $PANE"
query=$(ur_scrollback_topic "$scrollback" "$self_topic") \
  || die "no prior \$topic marker found in scrollback"

uuid=$(ur_resolve_uuid "$PROJECTS" "$slug" "$query" "$self") \
  || die "no prior session matches topic: $query"

# Self-inject the resume. Mirror claude-resume.sh:
#   1. @ct_resuming so .zshrc precmd mutes the phantom prompt-ready Pop the resume
#      redraw triggers (per-pane option dies with the pane).
#   2. C-u clears any half-typed input on the prompt first.
#   3. "/resume <uuid>" + Enter — the slash command (Claude is already running),
#      NOT `claude --resume` (that's the external entrypoint's job).
TMUX= "$TMUX_BIN" set-option -p -t "$PANE" @ct_resuming 1 2>/dev/null || true
TMUX= "$TMUX_BIN" send-keys -t "$PANE" C-u 2>/dev/null || true
TMUX= "$TMUX_BIN" send-keys -t "$PANE" "/resume $uuid" Enter \
  || die "could not send resume keys to $PANE"

printf 'ultraresume → /resume %s  (topic: %s)\n' "$uuid" "$query"
