#!/bin/bash
# auto-dev-install.sh — SwiftBar "Install Auto-dev to repo…" action
# Phase 1 (here): show native repo picker dialog — no terminal needed.
# Phase 2 (Terminal.app): run runner-setup.sh with the chosen repo.
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

SCRIPTS_DIR='{{scripts_dir}}'
SETUP="$SCRIPTS_DIR/auto-dev-runner-setup.sh"
JQ={{jq}}
CANDIDATES_CACHE="/tmp/claude-toolkit-auto-dev-candidates.json"

# ── Build repo list ──────────────────────────────────────
if [[ -f "$CANDIDATES_CACHE" ]]; then
  REPO_LIST=$($JQ -r '.repos[]?' "$CANDIDATES_CACHE" 2>/dev/null)
else
  REPO_LIST=$(gh repo list --json nameWithOwner,repositoryTopics --limit 50 2>/dev/null \
    | $JQ -r '[.[] | select((.repositoryTopics // []) | map(.name) | contains(["auto-dev"]) | not) | .nameWithOwner] | sort | .[]' 2>/dev/null)
fi

if [[ -z "$REPO_LIST" ]]; then
  osascript -e 'display alert "Auto-dev Setup" message "No candidate repos found. Check gh auth and try Refresh caches." as warning' >/dev/null
  exit 0
fi

# ── Show picker ──────────────────────────────────────────
AS_ITEMS=$(echo "$REPO_LIST" | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')
REPO=$(osascript <<ASEOF 2>/dev/null
set repoList to {$AS_ITEMS}
set chosen to choose from list repoList with prompt "Install auto-dev into which repo?" with title "Auto-dev Setup" OK button name "Install" cancel button name "Cancel"
if chosen is false then return ""
return item 1 of chosen
ASEOF
)

[[ -z "$REPO" ]] && exit 0

# ── Phase 2: open Terminal.app with chosen repo ──────────
osascript \
  -e 'tell application "Terminal"' \
  -e '  activate' \
  -e "  do script \"'$SETUP' '$REPO'; echo ''; echo 'Setup complete. Close this window.'; read\"" \
  -e 'end tell'
