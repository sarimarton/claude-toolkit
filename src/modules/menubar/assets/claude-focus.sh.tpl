#!/usr/bin/env bash
# claude-focus.sh — Focus an attached Claude session's terminal tab.
# Uses tmux window rename + JXA AX tree scanning (same marker technique as HS version).
# Usage: claude-focus.sh <session_name>

notify_failure() {
    local title="$1"
    local detail="$2"
    logger -t claude-toolkit "FAIL: $title — $detail" 2>/dev/null || true
    osascript -e "display notification \"$detail\" with title \"$title\"" >/dev/null 2>&1 || true
}

SESSION="$1"
if [[ -z "$SESSION" ]]; then
    notify_failure "Claude focus failed" "No session name provided"
    exit 1
fi

TMUX_BIN={{tmux}}
MARKER="FOCUS:$SESSION"

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

# Verify session exists before any window-rename gymnastics
if ! TMUX= $TMUX_BIN has-session -t "$SESSION" 2>/dev/null; then
    notify_failure "Claude focus failed" "Session does not exist: $SESSION"
    exit 1
fi

# Save original window name
ORIG=$(TMUX= $TMUX_BIN display-message -t "$SESSION" -p '#{window_name}' 2>/dev/null | tr -d '\n')

# Set marker as window name (propagates to tab title via set-titles-string "#W")
TMUX= $TMUX_BIN rename-window -t "$SESSION" "$MARKER" 2>/dev/null
sleep 0.15

# Scan native terminal apps for the marker via JXA
osascript -l JavaScript -e "
    const marker = '$MARKER';
    const apps = ['Ghostty', 'Terminal'];

    const se = Application('System Events');

    for (const appName of apps) {
        try {
            const proc = se.processes.byName(appName);
            if (!proc.exists()) continue;

            const wins = proc.windows();
            for (let wi = 0; wi < wins.length; wi++) {
                const win = wins[wi];

                // Multi-tab: scan AXTabGroup children
                const children = win.uiElements();
                for (let ci = 0; ci < children.length; ci++) {
                    const child = children[ci];
                    if (child.role() === 'AXTabGroup') {
                        const tabs = child.uiElements();
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
    # don't early-exit — still attempt to restore the original window name below
fi

# Restore original window name
TMUX= $TMUX_BIN rename-window -t "$SESSION" "$ORIG" 2>/dev/null
