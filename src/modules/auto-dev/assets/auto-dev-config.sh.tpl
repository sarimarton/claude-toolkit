#!/usr/bin/env bash
# auto-dev-config.sh — Edit per-repo auto-dev config via AppleScript form.
# Config is stored as JSON in a GitHub Actions repo variable: AUTO_DEV_CONFIG
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

REPO="$1"
[[ -z "$REPO" ]] && exit 0

JQ={{jq}}

# ── Read current config ───────────────────────────────────────
RAW=$(gh api "repos/$REPO/actions/variables/AUTO_DEV_CONFIG" --jq '.value' 2>/dev/null || echo '{}')
CONFIG=$(echo "$RAW" | $JQ -c '.' 2>/dev/null || echo '{}')

CI=$(echo "$CONFIG" | $JQ -r '.create_issues    // true')
CP=$(echo "$CONFIG" | $JQ -r '.create_prs       // true')
PC=$(echo "$CONFIG" | $JQ -r '.push_commits     // true')
MI=$(echo "$CONFIG" | $JQ -r '.max_issues_per_run // 3')

# ── AppleScript form (sequential dialogs) ────────────────────
RESULT=$(osascript <<ASEOF 2>/dev/null
-- create_issues
set ciList to {"true", "false"}
set ciResult to choose from list ciList with prompt "create_issues — Can Claude open sub-issues automatically?" with title "Auto-dev Config: $REPO" default items {"$CI"}
if ciResult is false then return "cancelled"
set ciVal to item 1 of ciResult

-- create_prs
set cpList to {"true", "false"}
set cpResult to choose from list cpList with prompt "create_prs — Can Claude open draft PRs automatically?" with title "Auto-dev Config: $REPO" default items {"$CP"}
if cpResult is false then return "cancelled"
set cpVal to item 1 of cpResult

-- push_commits
set pcList to {"true", "false"}
set pcResult to choose from list pcList with prompt "push_commits — Can Claude push commits automatically?" with title "Auto-dev Config: $REPO" default items {"$PC"}
if pcResult is false then return "cancelled"
set pcVal to item 1 of pcResult

-- max_issues_per_run
set miResult to display dialog "max_issues_per_run — Max issues to process per scheduled run:" default answer "$MI" with title "Auto-dev Config: $REPO" buttons {"Cancel", "Save"} default button "Save" cancel button "Cancel"
set miVal to text returned of miResult

return ciVal & "|" & cpVal & "|" & pcVal & "|" & miVal
ASEOF
)

[[ -z "$RESULT" || "$RESULT" == "cancelled" ]] && exit 0

IFS='|' read -r NEW_CI NEW_CP NEW_PC NEW_MI <<< "$RESULT"

# Validate numeric field
if ! [[ "$NEW_MI" =~ ^[0-9]+$ ]] || (( NEW_MI < 1 || NEW_MI > 20 )); then
  osascript -e 'display alert "Invalid input" message "max_issues_per_run must be a number between 1 and 20." as warning' >/dev/null
  exit 1
fi

NEW_CONFIG=$($JQ -nc \
  --argjson create_issues     "$NEW_CI" \
  --argjson create_prs        "$NEW_CP" \
  --argjson push_commits      "$NEW_PC" \
  --argjson max_issues_per_run "$NEW_MI" \
  '{create_issues: $create_issues, create_prs: $create_prs, push_commits: $push_commits, max_issues_per_run: $max_issues_per_run}')

# POST if not yet exists, PATCH if it does
if gh api "repos/$REPO/actions/variables/AUTO_DEV_CONFIG" &>/dev/null 2>&1; then
  HTTP_METHOD="PATCH"
  API_PATH="repos/$REPO/actions/variables/AUTO_DEV_CONFIG"
else
  HTTP_METHOD="POST"
  API_PATH="repos/$REPO/actions/variables"
fi

if gh api -X "$HTTP_METHOD" "$API_PATH" -f name="AUTO_DEV_CONFIG" -f value="$NEW_CONFIG" >/dev/null 2>&1; then
  osascript -e "display notification \"Config saved for $REPO\" with title \"Auto-dev\"" >/dev/null || true
else
  osascript -e 'display alert "Save failed" message "Could '\''t write repo variable. Make sure '\''gh'\'' has repo/actions write scope (gh auth refresh -s repo)." as warning' >/dev/null
fi
