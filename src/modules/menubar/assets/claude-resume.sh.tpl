#!/usr/bin/env bash
# claude-resume.sh — Resume a dead (rebooted/crashed) Claude session in its restored
# tmux pane, then attach a terminal tab to it. Triggered by the menu's hollow orange ○.
# The pane and UUID are resolved by the menu at render time from the resume index.
# Usage: claude-resume.sh [--no-attach] <session_name> <pane_id> <uuid>
#
# --no-attach: skip the final claude-attach.sh (terminal-tab) step. Used by the
# auto-resume-on-attach path (claude-auto-resume.sh, fired from tmux's
# client-attached hook): the tab is already open and focused there, so opening
# another would fight the client that just attached. The menu's manual ○ path
# omits the flag — it needs the attach to bring the user into the resumed pane.

notify_failure() {
    local title="$1"
    local detail="$2"
    logger -t claude-toolkit "FAIL: $title — $detail" 2>/dev/null || true
    osascript -e "display notification \"$detail\" with title \"$title\"" >/dev/null 2>&1 || true
}

NO_ATTACH=false
if [[ "$1" == "--no-attach" ]]; then
    NO_ATTACH=true
    shift
fi

SESSION="$1"
PANE="$2"
UUID="$3"
if [[ -z "$SESSION" || -z "$PANE" || -z "$UUID" ]]; then
    notify_failure "Claude resume failed" "Missing arguments (session/pane/uuid)"
    exit 1
fi

TMUX_BIN={{tmux}}
CLAUDE_BIN={{claude}}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If Claude already came back in this pane (e.g. a double-click, or auto-resume
# already fired for it), skip the relaunch. With --no-attach this is a pure no-op
# (idempotent — the auto-resume path may revisit a pane it already resumed); the
# menu path still brings the existing tab forward.
cur=$(TMUX= $TMUX_BIN display-message -t "$PANE" -p '#{pane_current_command}' 2>/dev/null)
# Claude is alive if the pane command is a version string (direct launch) or the bare
# word "claude" (stable-claude-bin PATH shim execs the launcher under that name).
if [[ "$cur" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "$cur" == "claude" ]]; then
    $NO_ATTACH || "$SCRIPT_DIR/claude-attach.sh" "$SESSION"
    exit 0
fi

# Verify the pane still exists before sending keys into it.
if ! TMUX= $TMUX_BIN display-message -t "$PANE" -p '' >/dev/null 2>&1; then
    notify_failure "Claude resume failed" "Pane no longer exists: $PANE"
    exit 1
fi

# Mark this pane as auto-resuming so .zshrc's precmd mutes the prompt-ready Pop for
# the single redraw the resumed Claude triggers (a -CC client reconnect fires this
# with no human at the keyboard — the phantom Pop). precmd consumes the marker, so
# the next real prompt sounds normally. Per-pane tmux option = dies with the pane.
TMUX= $TMUX_BIN set-option -p -t "$PANE" @ct_resuming 1 2>/dev/null

# Clear any stray input on the prompt, then launch the resume in the pane itself.
# Running it inside the pane (not a detached process) keeps the session bound to its
# tmux window, exactly where it was before the reboot.
TMUX= $TMUX_BIN send-keys -t "$PANE" C-u 2>/dev/null
if ! TMUX= $TMUX_BIN send-keys -t "$PANE" "$CLAUDE_BIN --resume $UUID" Enter 2>/dev/null; then
    notify_failure "Claude resume failed" "Could not send resume command to pane $PANE"
    exit 1
fi

# Open/attach a terminal tab so the user lands in the resumed session.
# Skipped under --no-attach (auto-resume: the attaching client is already there).
$NO_ATTACH || "$SCRIPT_DIR/claude-attach.sh" "$SESSION"
