#!/usr/bin/env bash
# auto-dev-gh-fix-scope.sh — SwiftBar action: grant gh the `project` scope.
# `gh auth refresh` is interactive (opens the browser), so this is the one
# auto-dev action that legitimately opens a Terminal window.
export PATH="{{home}}/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

# Invalidate the menu's cached scope result so the warning clears on next render.
rm -f /tmp/.auto-dev-gh-scope

osascript \
  -e 'tell application "Terminal"' \
  -e '  activate' \
  -e "  do script \"gh auth refresh -s project,read:project; echo ''; echo 'Done. Close this window.'; read\"" \
  -e 'end tell'
