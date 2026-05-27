#!/bin/bash
# auto-dev-reinstall.sh — SwiftBar "Reinstall Auto-dev…" action for a managed repo.
# Phase 1: confirmation dialog. Phase 2: open Terminal.app running runner-setup.sh.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

REPO="$1"
[[ -z "$REPO" ]] && exit 0

PUSH='{{scripts_dir}}/auto-dev-workflow-push.sh'

CONFIRM=$(osascript <<ASEOF 2>/dev/null
display dialog "Update auto-dev workflow files for $REPO?

This will push the latest workflow files. The runner is not affected." with title "Update Auto-dev Workflows" buttons {"Cancel", "Update"} default button "Update" cancel button "Cancel"
return button returned of result
ASEOF
)

[[ "$CONFIRM" != "Update" ]] && exit 0

osascript \
  -e 'tell application "Terminal"' \
  -e '  activate' \
  -e "  do script \"'$PUSH' '$REPO'; echo ''; echo 'Update complete. Close this window.'; read\"" \
  -e 'end tell'
