#!/usr/bin/env bash
# claude-attach.sh — Attach to a detached Claude session by opening a new terminal tab.
# Terminal is configurable via modules.menubar.terminal (default: iterm).
#   iterm   — open a new iTerm tab running `tmux attach-session` directly.
#   ghostty — write a signal file and let ghostty-tmux.sh pick it up (legacy flow).
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

# ── Read the configured terminal live from config.yaml (default: iterm) ──
# Read at runtime (not baked in), so changing the config takes effect without a reinstall.
CONFIG_FILE="{{config_file}}"
TMUX_BIN={{tmux}}
TERMINAL=iterm
if [[ -f "$CONFIG_FILE" ]]; then
    cfg=$({{yq}} -r '.modules.menubar.terminal // "iterm"' "$CONFIG_FILE" 2>/dev/null)
    case "$cfg" in iterm|ghostty) TERMINAL="$cfg" ;; esac
fi

attach_iterm() {
    # Open a new iTerm tab (or a window if none exists) and attach directly.
    # `exec` replaces the shell with tmux, so detaching/closing the session closes the tab.
    local cmd="exec $TMUX_BIN attach-session -t '$SESSION'"
    osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "iTerm"
    activate
    if (count of windows) = 0 then
        set w to (create window with default profile)
        tell current session of w to write text "$cmd"
    else
        tell current window
            set t to (create tab with default profile)
            tell current session of t to write text "$cmd"
        end tell
    end if
end tell
APPLESCRIPT
    if [[ $? -ne 0 ]]; then
        notify_failure "Claude attach failed" "Could not open iTerm tab (Automation permission?)"
        exit 1
    fi
}

attach_ghostty() {
    local ATTACH_SIGNAL="/tmp/.ghostty-attach"
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
}

case "$TERMINAL" in
    ghostty) attach_ghostty ;;
    *)       attach_iterm ;;
esac
