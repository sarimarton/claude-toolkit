#!/bin/sh
# auto-dev-install.sh — SwiftBar "Install Auto-dev to repo…" action
# Opens Terminal.app via osascript to avoid SwiftBar terminal=true zsh bugs.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"
SETUP='{{scripts_dir}}/auto-dev-runner-setup.sh'
osascript \
  -e 'tell application "Terminal"' \
  -e '  activate' \
  -e "  do script \"'$SETUP'; echo ''; echo 'Setup complete. Close this window.'; read\"" \
  -e 'end tell'
