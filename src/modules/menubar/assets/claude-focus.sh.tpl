#!/usr/bin/env bash
# claude-focus.sh — Focus an attached Claude session's terminal tab.
# Uses tmux window rename + JXA AX tree scanning (same marker technique as HS version).
# Usage: claude-focus.sh <session_name>

SESSION="$1"
[[ -z "$SESSION" ]] && exit 1

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

# Restore original window name
TMUX= $TMUX_BIN rename-window -t "$SESSION" "$ORIG" 2>/dev/null
