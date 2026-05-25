#!/bin/sh
# claude-toolkit-update.sh — menubar update action
# Opens Terminal.app directly via osascript to avoid SwiftBar terminal=true
# zsh history expansion bugs (! in env var values like OS_APPEARANCE=Dark).
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"
REPO='{{repo_dir}}'
osascript \
  -e 'tell application "Terminal"' \
  -e '  activate' \
  -e "  do script \"node '$REPO/dist/cli.js' update; echo ''; echo 'Update complete. Close this window.'; read\"" \
  -e 'end tell'
