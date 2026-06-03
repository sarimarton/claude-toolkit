#!/usr/bin/env bash
# claude-resume-cleanup.sh — Remove a dead (restorable) session from the menu.
# Triggered by the Option-held ✕ on a hollow gray ○ entry. The Claude process is
# already gone; what lingers is (a) the resume-index rows for this (session,
# window-name) and (b) the shell pane tmux-resurrect brought back. Drop both so
# the dead topic disappears entirely, then reopen the SwiftBar menu.
# Usage: claude-resume-cleanup.sh <session_name> <window_name> <pane_id>

notify_failure() {
    local title="$1"
    local detail="$2"
    logger -t claude-toolkit "FAIL: $title — $detail" 2>/dev/null || true
    osascript -e "display notification \"$detail\" with title \"$title\"" >/dev/null 2>&1 || true
}

SESSION="$1"
WIN_NAME="$2"
PANE="$3"
if [[ -z "$SESSION" || -z "$WIN_NAME" ]]; then
    notify_failure "Claude cleanup failed" "Missing arguments (session/window)"
    exit 1
fi

TMUX_BIN={{tmux}}
RESUME_INDEX="{{state_dir}}/resume-index.tsv"

# Drop every index row for this (session, window-name) so the entry is gone for good.
if [[ -f "$RESUME_INDEX" ]]; then
    tmp_idx="$RESUME_INDEX.$$.tmp"
    awk -F'\t' -v s="$SESSION" -v w="$WIN_NAME" '!($1==s && $2==w)' "$RESUME_INDEX" 2>/dev/null > "$tmp_idx" \
        && mv -f "$tmp_idx" "$RESUME_INDEX"
fi

# Close the resurrected shell pane. Guard: only if it still runs a plain shell —
# never kill a pane where Claude (a version-like command) has since come back.
if [[ -n "$PANE" ]]; then
    cur=$(TMUX= $TMUX_BIN display-message -t "$PANE" -p '#{pane_current_command}' 2>/dev/null)
    if [[ -n "$cur" && ! "$cur" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        TMUX= $TMUX_BIN kill-pane -t "$PANE" 2>/dev/null || true
    fi
fi

# Refresh plugin data, then reopen the menu via a synthetic click (the menu is a
# native NSMenu that the originating click dismissed — same trick as claude-kill).
open -g "swiftbar://refreshplugin?name=claude.10s"
sleep 0.5
osascript -l JavaScript -e "
ObjC.import('CoreGraphics');
var se = Application('System Events');
var items = se.processes.byName('SwiftBar').menuBars[0].menuBarItems;
var item = null;
for (var i = 0; i < items.length; i++) {
    if ((items[i].name() || '').indexOf('✻') !== -1) { item = items[i]; break; }
}
if (!item) { item = items[items.length - 1]; }
var pos = item.position();
var sz = item.size();
var cx = pos[0] + sz[0]/2, cy = pos[1] + sz[1]/2;
var pt = $.CGPointMake(cx, cy);
var dn = $.CGEventCreateMouseEvent(null, $.kCGEventLeftMouseDown, pt, 0);
var up = $.CGEventCreateMouseEvent(null, $.kCGEventLeftMouseUp, pt, 0);
$.CGEventPost($.kCGHIDEventTap, dn);
delay(0.05);
$.CGEventPost($.kCGHIDEventTap, up);
" &>/dev/null &
