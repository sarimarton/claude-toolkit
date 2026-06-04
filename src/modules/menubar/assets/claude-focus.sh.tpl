#!/usr/bin/env bash
# claude-focus.sh — Focus an attached Claude session's terminal tab.
# Uses tmux window rename + JXA AX tree scanning (same marker technique as HS version).
# Usage: claude-focus.sh <session_name> [window_id]
#
# window_id (e.g. "@11") pins the marker to the EXACT window that holds the clicked
# pane. Without it, `rename-window -t <session>` retargets the session's *active*
# window — so in a multi-window session the marker (and thus the focus) lands on the
# wrong tab. The menu passes #{window_id} for every attached entry; we fall back to
# the session name (legacy behaviour) only if it is missing.

notify_failure() {
    local title="$1"
    local detail="$2"
    logger -t claude-toolkit "FAIL: $title — $detail" 2>/dev/null || true
    osascript -e "display notification \"$detail\" with title \"$title\"" >/dev/null 2>&1 || true
}

SESSION="$1"
WINDOW_ID="$2"
if [[ -z "$SESSION" ]]; then
    notify_failure "Claude focus failed" "No session name provided"
    exit 1
fi

TMUX_BIN={{tmux}}
MARKER="FOCUS:$SESSION"

# Target the specific window holding the clicked pane when we know it; otherwise the
# session (legacy). The marker becomes that window's name, so each window — i.e. each
# native iTerm -CC tab / Ghostty tab — gets a distinct, scannable tab title.
TARGET="${WINDOW_ID:-$SESSION}"

# VS Code sessions: use URI handler
if [[ "$SESSION" == vscode_* ]]; then
    pid="${SESSION##*_}"
    # Find VS Code window by pane path
    path=$(TMUX= $TMUX_BIN display-message -t "$SESSION" -p '#{pane_current_path}' 2>/dev/null | tr -d '\n')
    open -a "Visual Studio Code"
    sleep 0.2
    open "vscode://sarim.vscode-terminal-topic/focus?pid=$pid"
    exit 0
fi

# Verify the target window/session exists before any window-rename gymnastics
if ! TMUX= $TMUX_BIN has-session -t "$TARGET" 2>/dev/null; then
    notify_failure "Claude focus failed" "Session does not exist: $SESSION"
    exit 1
fi

# Save original window name
ORIG=$(TMUX= $TMUX_BIN display-message -t "$TARGET" -p '#{window_name}' 2>/dev/null | tr -d '\n')

restore_window_name() {
    # Idempotent: safe to call multiple times. Best-effort — if the session
    # disappeared, just silently move on.
    [ -n "$ORIG" ] && TMUX= $TMUX_BIN rename-window -t "$TARGET" "$ORIG" 2>/dev/null || true
}
trap restore_window_name EXIT

# Set marker as window name (propagates to tab title via set-titles-string "#W")
TMUX= $TMUX_BIN rename-window -t "$TARGET" "$MARKER" 2>/dev/null
sleep 0.15

# Scan native terminal apps for the marker via JXA
osascript -l JavaScript -e "
    const marker = '$MARKER';
    // iTerm2 renders tmux -CC windows as native tabs whose AX title is the tmux
    // window name, so the same AXTabGroup scan that works for Ghostty/Terminal also
    // finds them — once the marker is pinned to the right window (see TARGET above).
    const apps = ['iTerm2', 'Ghostty', 'Terminal'];

    const se = Application('System Events');

    // Recursively find AXTabGroups at any depth. Ghostty/Terminal expose the tab
    // group as a direct window child, but iTerm2 nests it inside split/scroll
    // groups — a flat first-level scan misses it. Depth-cap guards pathological trees.
    function collectTabGroups(el, depth, acc) {
        if (depth > 6) return;
        let kids;
        try { kids = el.uiElements(); } catch(e) { return; }
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i];
            let role = '';
            try { role = k.role(); } catch(e) { continue; }
            if (role === 'AXTabGroup') acc.push(k);
            else collectTabGroups(k, depth + 1, acc);
        }
    }

    for (const appName of apps) {
        try {
            const proc = se.processes.byName(appName);
            if (!proc.exists()) continue;

            const wins = proc.windows();
            for (let wi = 0; wi < wins.length; wi++) {
                const win = wins[wi];

                // Multi-tab: scan AXTabGroups (at any nesting depth)
                const groups = [];
                collectTabGroups(win, 0, groups);
                for (let gi = 0; gi < groups.length; gi++) {
                    const tabs = groups[gi].uiElements();
                    for (let ti = 0; ti < tabs.length; ti++) {
                        try {
                            if ((tabs[ti].title() || '').includes(marker)) {
                                proc.frontmost = true;
                                win.actions.byName('AXRaise').perform();
                                tabs[ti].actions.byName('AXPress').perform();
                                marker; // signal found
                            }
                        } catch(e) {}
                    }
                }

                // Single-tab: check window title
                try {
                    if ((win.title() || '').includes(marker)) {
                        proc.frontmost = true;
                        win.actions.byName('AXRaise').perform();
                    }
                } catch(e) {}
            }
        } catch(e) {}
    }
" 2>/dev/null
osa_rc=$?
if [ $osa_rc -ne 0 ]; then
    notify_failure "Claude focus failed" "AppleScript scan failed (Accessibility permission?)"
    # trap on EXIT will still restore the original window name
fi

# Window name restore handled by EXIT trap (runs on success, failure, or signal)
