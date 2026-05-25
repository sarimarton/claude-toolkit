#!/bin/sh
# claude-toolkit-update.sh — menubar update action
# Opens Terminal.app via osascript (avoids SwiftBar terminal=true zsh bugs).
# Uses the claude-toolkit binary (symlinked to actual install location),
# NOT a hardcoded repo path — important when devving from a separate clone.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"
osascript <<'ASEOF'
tell application "Terminal"
  activate
  do script "claude-toolkit update; echo; echo 'Update complete. Close this window.'; read"
end tell
ASEOF
