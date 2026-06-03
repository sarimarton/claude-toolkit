#!/usr/bin/env bash
# claude-attach.sh — Attach to a detached Claude session by opening a new terminal tab.
# Terminal is configurable via modules.menubar.terminal (default: iterm).
#   iterm   — open a new iTerm tab running `tmux attach-session` (see attach mode below).
#   ghostty — write a signal file and let ghostty-tmux.sh pick it up (legacy flow).
#
# iTerm attach mode is configurable via modules.menubar.iterm_attach (default: cc):
#   cc    — `tmux -CC attach` → iTerm renders the session as native tabs/windows.
#           Trade-off: tmux's own overlays (display-popup, fzf-tmux -p, status line)
#           are NOT rendered natively, so popup-based UIs like the prefix-e fzf picker
#           do not appear in -CC tabs.
#   plain — `tmux attach` → tmux renders into the terminal itself (like Ghostty). You
#           lose native-tab integration but gain the full tmux UI: status line and,
#           crucially, the display-popup fzf session/window picker (prefix-e) works.
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
ITERM_ATTACH=cc
if [[ -f "$CONFIG_FILE" ]]; then
    cfg=$({{yq}} -r '.modules.menubar.terminal // "iterm"' "$CONFIG_FILE" 2>/dev/null)
    case "$cfg" in iterm|ghostty) TERMINAL="$cfg" ;; esac
    acfg=$({{yq}} -r '.modules.menubar.iterm_attach // "cc"' "$CONFIG_FILE" 2>/dev/null)
    case "$acfg" in cc|plain) ITERM_ATTACH="$acfg" ;; esac
fi

attach_iterm() {
    # Open a new iTerm tab (or a window if none exists) and attach in tmux.
    #
    # The launch command is passed via the AppleScript `command` parameter, which
    # OVERRIDES the default profile's Custom Command (which would otherwise run
    # `tmux -CC new-session -A -s main`). Without this override the tab runs two
    # tmux invocations — the profile's `main` attach AND our attach — producing a
    # nested control-mode session that iTerm dumps as raw `%extended-output` text
    # ("Cannot attach — already attached to this session").
    local cmd
    if [[ "$ITERM_ATTACH" == "plain" ]]; then
        # Plain attach: tmux renders into the terminal itself, so display-popup /
        # fzf-tmux overlays (the prefix-e picker) work. No -CC, no OpenTmuxWindowsIn.
        cmd="$TMUX_BIN attach-session -t '$SESSION'"
    else
        # Control mode (-CC): iTerm — not AppleScript — decides where the session
        # opens, via the "Open tmux windows as" preference (OpenTmuxWindowsIn):
        # 0=native windows, 1=tabs in a new window, 2=tabs in the attaching window.
        # Unset defaults to a new native window, which is why a fresh window popped
        # open. We want the session as a tab in the existing window → 2. Only set when
        # unset, so an explicit user choice is never overridden (iTerm may apply it on
        # its next launch).
        if ! defaults read com.googlecode.iterm2 OpenTmuxWindowsIn >/dev/null 2>&1; then
            defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2 2>/dev/null || true
        fi
        cmd="$TMUX_BIN -CC attach-session -t '$SESSION'"
    fi
    osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "iTerm"
    activate
    if (count of windows) = 0 then
        create window with default profile command "$cmd"
    else
        tell current window
            create tab with default profile command "$cmd"
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
