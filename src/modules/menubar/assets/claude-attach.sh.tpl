#!/usr/bin/env bash
# claude-attach.sh — Attach to a detached Claude session by opening a new Ghostty tab.
# Uses the same signal file mechanism as the Hammerspoon version.
# Usage: claude-attach.sh <session_name>

notify_failure() {
    local title="$1"
    local detail="$2"
    logger -t claude-toolkit "FAIL: $title — $detail" 2>/dev/null || true
    osascript -e "display notification \"$detail\" with title \"$title\"" >/dev/null 2>&1 || true
}

SESSION="$1"
if [[ -z "$SESSION" ]]; then
    notify_failure "Claude attach failed" "No session name provided"
    exit 1
fi

ATTACH_SIGNAL="/tmp/.ghostty-attach"

# Write signal file for ghostty-tmux.sh to pick up
if ! echo "$SESSION" > "$ATTACH_SIGNAL" 2>/dev/null; then
    notify_failure "Claude attach failed" "Could not write signal file: $ATTACH_SIGNAL"
    exit 1
fi

# Activate Ghostty and open a new tab (or launch it if not running)
if pgrep -qf "Ghostty"; then
    if ! osascript -e 'tell application "Ghostty" to activate' 2>/dev/null; then
        notify_failure "Claude attach failed" "Could not activate Ghostty (AppleScript denied?)"
        exit 1
    fi
    sleep 0.2
    if ! osascript -e 'tell application "System Events" to tell process "Ghostty" to keystroke "t" using command down' 2>/dev/null; then
        notify_failure "Claude attach failed" "Could not open new Ghostty tab (Accessibility permission?)"
        exit 1
    fi
else
    if ! open -a Ghostty 2>/dev/null; then
        notify_failure "Claude attach failed" "Could not launch Ghostty"
        exit 1
    fi
fi
