#!/bin/bash
# auto-dev-reinstall.sh — SwiftBar "Reinstall Auto-dev…" action for a managed repo.
# Phase 1: confirmation dialog. Phase 2: open Terminal.app running runner-setup.sh.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

REPO="$1"
[[ -z "$REPO" ]] && exit 0

SETUP='{{scripts_dir}}/auto-dev-runner-setup.sh'

CONFIRM=$(osascript <<ASEOF 2>/dev/null
display dialog "Reinstall auto-dev for $REPO?

This will re-register the runner and re-push the workflow." with title "Auto-dev Reinstall" buttons {"Cancel", "Reinstall"} default button "Reinstall" cancel button "Cancel"
return button returned of result
ASEOF
)

[[ "$CONFIRM" != "Reinstall" ]] && exit 0

osascript \
  -e 'tell application "Terminal"' \
  -e '  activate' \
  -e "  do script \"'$SETUP' '$REPO'; echo ''; echo 'Reinstall complete. Close this window.'; read\"" \
  -e 'end tell'
