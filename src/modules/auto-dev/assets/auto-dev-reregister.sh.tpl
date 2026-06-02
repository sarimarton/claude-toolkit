#!/bin/bash
# auto-dev-reregister.sh — SwiftBar "Re-register Runner…" action for a managed repo.
# Phase 1: confirmation dialog. Phase 2: open Terminal.app running runner-setup.sh.
export PATH="{{home}}/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

REPO="$1"
[[ -z "$REPO" ]] && exit 0

SETUP='{{scripts_dir}}/auto-dev-runner-setup.sh'

CONFIRM=$(osascript <<ASEOF 2>/dev/null
display dialog "Re-register runner for $REPO?

This will stop any running jobs and re-register the runner." with title "Re-register Runner" buttons {"Cancel", "Re-register"} default button "Re-register" cancel button "Cancel"
return button returned of result
ASEOF
)

[[ "$CONFIRM" != "Re-register" ]] && exit 0

osascript \
  -e 'tell application "Terminal"' \
  -e '  activate' \
  -e "  do script \"'$SETUP' '$REPO'; echo ''; echo 'Re-registration complete. Close this window.'; read\"" \
  -e 'end tell'
