#!/bin/bash
SESSION="ghostty_$$"
SIGNAL="/tmp/.ghostty-claude"
ATTACH_SIGNAL="/tmp/.ghostty-attach"

# Track close signals: Ghostty may send HUP, TERM, or just destroy the PTY
GOT_CLOSE=false
trap 'GOT_CLOSE=true' HUP TERM

# Detect tab close: signal received OR controlling terminal destroyed
# Returns 0 (true) if tab was closed, 1 (false) if clean detach
tab_was_closed() {
    $GOT_CLOSE && return 0
    # No signal — check if PTY is still alive (detach keeps it, tab close destroys it)
    stty size >/dev/null 2>&1 && return 1
    return 0
}

QUIT_MARKER="/tmp/.ghostty-quitting"
HS=/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs

# Kill tmux session on Alt+close (not detach, not plain close, not app quit)
cleanup() {
    local session="$1"
    tab_was_closed || return
    # Check Alt modifier IMMEDIATELY (before user releases the key)
    local alt_held
    alt_held=$($HS -c "hs.eventtap.checkKeyboardModifiers().alt" 2>/dev/null)
    [[ "$alt_held" != "true" ]] && return
    # Wait for Ghostty to fully quit — 1.5s is invisible (tab is already closed visually)
    sleep 1.5
    # Sibling script already detected app quit → preserve
    if [[ -f "$QUIT_MARKER" ]]; then return; fi
    # Ghostty app quit → mark for siblings and preserve sessions for restore
    if ! pgrep -x ghostty >/dev/null 2>&1; then
        touch "$QUIT_MARKER"
        return
    fi
    # Session already gone (Cmd+W / prefix+Q killed it)
    {{tmux}} has-session -t "$session" 2>/dev/null || return
    {{tmux}} kill-session -t "$session" 2>/dev/null
}

# Attach signal → menu bar click on unattached session → direct attach
# Cmd+W (kill-session) and native tab close both kill the session
if [[ -f "$ATTACH_SIGNAL" ]]; then
    TARGET=$(cat "$ATTACH_SIGNAL")
    rm -f "$ATTACH_SIGNAL"
    {{tmux}} attach-session -t "$TARGET"
    cleanup "$TARGET"
    exit 0
fi

# Signal file present → Ctrl+Cmd+T/N triggered this tab → start claude
# No signal → regular Cmd+T/N → start zsh
# Sessions persist through Ghostty quit/restart; Cmd+W (prefix+Q) or native tab close kills them
if [[ -f "$SIGNAL" ]]; then
    rm -f "$SIGNAL"
    {{tmux}} new-session -s "$SESSION" 'zsh -ic claude'
    cleanup "$SESSION"
    exit 0
fi

# Reattach to orphaned ghostty session from previous Ghostty quit/restart
# Sort by creation time (oldest first) so tab order is preserved on restore.
# rename-session is the atomic "claim" — if two tabs race, one rename fails (name gone)
rm -f "$QUIT_MARKER"
for s in $({{tmux}} list-sessions -F '#{session_created} #{session_name} #{session_attached}' 2>/dev/null \
    | sort -n | awk '/ghostty_/ && $3 == "0" { print $2 }'); do
    {{tmux}} rename-session -t "$s" "$SESSION" 2>/dev/null || continue
    {{tmux}} attach-session -t "$SESSION"
    cleanup "$SESSION"
    exit 0
done

# No orphans → fresh zsh session
{{tmux}} new-session -s "$SESSION"
cleanup "$SESSION"
