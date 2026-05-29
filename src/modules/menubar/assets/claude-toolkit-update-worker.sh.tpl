#!/bin/sh
# claude-toolkit-update-worker.sh — runs the actual update and posts a macOS
# notification on success/failure. Launched detached (tmux) by the menubar action
# so no Terminal window stays open. Full output goes to the log for inspection.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

LOG="/tmp/claude-toolkit-update.log"

if claude-toolkit update >"$LOG" 2>&1; then
  osascript -e 'display notification "✓ Update complete" with title "Claude Toolkit"' >/dev/null 2>&1
else
  osascript -e 'display notification "✗ Update failed — see /tmp/claude-toolkit-update.log" with title "Claude Toolkit"' >/dev/null 2>&1
fi
