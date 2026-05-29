#!/bin/sh
# claude-toolkit-update.sh — menubar update action.
# Runs the update silently in a detached tmux session (no Terminal window) and
# notifies via macOS notification on success/failure (handled by the worker).
# The worker is copied to /tmp first so `reinstall` (which rewrites scripts_dir)
# can't clobber it mid-run.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

TMUX_BIN={{tmux}}
SESSION="claude_toolkit_update"
WORKER="/tmp/claude-toolkit-update-worker.sh"

# Already updating? don't launch a second run.
$TMUX_BIN has-session -t "$SESSION" 2>/dev/null && exit 0

cp "{{scripts_dir}}/claude-toolkit-update-worker.sh" "$WORKER" 2>/dev/null && chmod +x "$WORKER" 2>/dev/null || exit 1
$TMUX_BIN new-session -d -s "$SESSION" "$WORKER"
