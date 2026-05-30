#!/usr/bin/env bash
# claude-resume.sh — Resume a dead (rebooted/crashed) Claude session in its restored
# tmux pane, then attach a terminal tab to it. Triggered by the menu's hollow orange ○.
# The pane and UUID are resolved by the menu at render time from the resume index.
# Usage: claude-resume.sh <session_name> <pane_id> <uuid>

notify_failure() {
    local title="$1"
    local detail="$2"
    logger -t claude-toolkit "FAIL: $title — $detail" 2>/dev/null || true
    osascript -e "display notification \"$detail\" with title \"$title\"" >/dev/null 2>&1 || true
}

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

# If Claude already came back in this pane (e.g. a double-click), skip the relaunch
# and just bring its terminal tab forward.
cur=$(TMUX= $TMUX_BIN display-message -t "$PANE" -p '#{pane_current_command}' 2>/dev/null)
if [[ "$cur" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    "$SCRIPT_DIR/claude-attach.sh" "$SESSION"
    exit 0
fi

# Verify the pane still exists before sending keys into it.
if ! TMUX= $TMUX_BIN display-message -t "$PANE" -p '' >/dev/null 2>&1; then
    notify_failure "Claude resume failed" "Pane no longer exists: $PANE"
    exit 1
fi

# Clear any stray input on the prompt, then launch the resume in the pane itself.
# Running it inside the pane (not a detached process) keeps the session bound to its
# tmux window, exactly where it was before the reboot.
TMUX= $TMUX_BIN send-keys -t "$PANE" C-u 2>/dev/null
if ! TMUX= $TMUX_BIN send-keys -t "$PANE" "$CLAUDE_BIN --resume $UUID" Enter 2>/dev/null; then
    notify_failure "Claude resume failed" "Could not send resume command to pane $PANE"
    exit 1
fi

# Open/attach a terminal tab so the user lands in the resumed session.
"$SCRIPT_DIR/claude-attach.sh" "$SESSION"
