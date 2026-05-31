#!/bin/bash
# auto-dev-reinstall.sh — SwiftBar "Update Auto-dev workflow files…" action.
# Phase 1: confirmation dialog. Phase 2: run the workflow push detached in a tmux
# session (no Terminal window) — mirrors the menubar "Update available" flow.
# The push script notifies on success itself; this launcher adds the failure path.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

REPO="$1"
[[ -z "$REPO" ]] && exit 0

TMUX_BIN={{tmux}}
PUSH='{{scripts_dir}}/auto-dev-workflow-push.sh'
LOG="/tmp/auto-dev-reinstall.log"

CONFIRM=$(osascript <<ASEOF 2>/dev/null
display dialog "Update auto-dev workflow files for $REPO?

This will push the latest workflow files. The runner is not affected." with title "Update Auto-dev Workflows" buttons {"Cancel", "Update"} default button "Update" cancel button "Cancel"
return button returned of result
ASEOF
)

[[ "$CONFIRM" != "Update" ]] && exit 0

# tmux session names can't contain '/' (repo is owner/repo) — sanitize.
SESSION="auto_dev_reinstall_$(echo "$REPO" | tr '/ ' '__')"

# A healthy push finishes in seconds; an existing session means a prior run stuck.
$TMUX_BIN kill-session -t "$SESSION" 2>/dev/null

$TMUX_BIN new-session -d -s "$SESSION" \
  "if '$PUSH' '$REPO' >'$LOG' 2>&1; then :; else osascript -e 'display notification \"✗ Update failed — see $LOG\" with title \"Claude Toolkit\" subtitle \"Auto-dev Reinstall\"'; fi"
