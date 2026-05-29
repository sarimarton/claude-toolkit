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
LAUNCH_LOG="/tmp/claude-toolkit-update-launch.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') launcher invoked (TMUX=${TMUX:-unset})" >> "$LAUNCH_LOG"

# Clear any leftover session: a healthy worker finishes in seconds, so an existing
# session means a previous run got stuck — never let that silently block updates.
$TMUX_BIN kill-session -t "$SESSION" 2>/dev/null

if ! cp "{{scripts_dir}}/claude-toolkit-update-worker.sh" "$WORKER" 2>>"$LAUNCH_LOG"; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') cp failed" >> "$LAUNCH_LOG"
  exit 1
fi
chmod +x "$WORKER" 2>>"$LAUNCH_LOG"

if $TMUX_BIN new-session -d -s "$SESSION" "$WORKER" 2>>"$LAUNCH_LOG"; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') worker launched" >> "$LAUNCH_LOG"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') new-session failed" >> "$LAUNCH_LOG"
  exit 1
fi
