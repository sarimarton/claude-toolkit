#!/usr/bin/env bash
# auto-dev-config.sh — Edit per-repo auto-dev config via gum TUI.
# Config is stored as JSON in a GitHub Actions repo variable: AUTO_DEV_CONFIG
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

REPO="$1"
[[ -z "$REPO" ]] && exit 0

# ── If not in a terminal, relaunch self in Terminal.app ───────
if [ ! -t 0 ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  osascript \
    -e 'tell application "Terminal"' \
    -e '  activate' \
    -e "  do script \"'$SELF' '$REPO'; echo ''; read -p 'Press Enter to close...'\"" \
    -e 'end tell'
  exit 0
fi

JQ={{jq}}

# ── Ensure gum is installed ───────────────────────────────────
if ! command -v gum &>/dev/null; then
  echo "Installing gum..."
  brew install gum
fi

# ── Read current config ───────────────────────────────────────
RAW=$(gh api "repos/$REPO/actions/variables/AUTO_DEV_CONFIG" --jq '.value' 2>/dev/null || echo '{}')
CONFIG=$(echo "$RAW" | $JQ -c '.' 2>/dev/null || echo '{}')
CURRENT_PRESET=$(echo "$CONFIG" | $JQ -r '.preset // "high"')

# ── Header ────────────────────────────────────────────────────
echo ""
gum style \
  --border rounded --border-foreground 212 \
  --padding "0 2" --bold \
  "Auto-dev Config: $REPO"
echo ""

# ── Preset selection ──────────────────────────────────────────
PRESET=$(gum choose \
  --header "Autonomy preset:" \
  --selected "$CURRENT_PRESET" \
  "high" "low" "custom")
[[ -z "$PRESET" ]] && exit 0

case "$PRESET" in
  high)
    # Fully autonomous: creates issues, PRs, pushes commits
    NEW_CI=true; NEW_CP=true; NEW_PC=true; NEW_MI=3
    ;;
  low)
    # Conservative: evaluates and comments, but no PRs or pushes without human approval
    NEW_CI=true; NEW_CP=false; NEW_PC=false; NEW_MI=1
    ;;
  custom)
    CURR_CI=$(echo "$CONFIG" | $JQ -r '.create_issues     // true')
    CURR_CP=$(echo "$CONFIG" | $JQ -r '.create_prs        // true')
    CURR_PC=$(echo "$CONFIG" | $JQ -r '.push_commits      // true')
    CURR_MI=$(echo "$CONFIG" | $JQ -r '.max_issues_per_run // 3')

    echo ""
    gum style --bold "Custom settings:"
    echo ""

    gum style "create_issues — Can Claude open sub-issues automatically?"
    NEW_CI=$(gum choose --selected "$CURR_CI" "true" "false")
    [[ -z "$NEW_CI" ]] && exit 0

    echo ""
    gum style "create_prs — Can Claude open draft PRs automatically?"
    NEW_CP=$(gum choose --selected "$CURR_CP" "true" "false")
    [[ -z "$NEW_CP" ]] && exit 0

    echo ""
    gum style "push_commits — Can Claude push commits automatically?"
    NEW_PC=$(gum choose --selected "$CURR_PC" "true" "false")
    [[ -z "$NEW_PC" ]] && exit 0

    echo ""
    gum style "max_issues_per_run — Max issues per scheduled run (1–20):"
    NEW_MI=$(gum input --value "$CURR_MI" --placeholder "1-20")
    [[ -z "$NEW_MI" ]] && exit 0

    if ! [[ "$NEW_MI" =~ ^[0-9]+$ ]] || (( NEW_MI < 1 || NEW_MI > 20 )); then
      gum style --foreground 1 "✗ max_issues_per_run must be a number between 1 and 20"
      exit 1
    fi
    ;;
esac

# ── Confirm ───────────────────────────────────────────────────
echo ""
gum confirm "Save config for $REPO?" || exit 0

# ── Build and write config ────────────────────────────────────
NEW_CONFIG=$($JQ -nc \
  --arg     preset           "$PRESET" \
  --argjson create_issues    "$NEW_CI" \
  --argjson create_prs       "$NEW_CP" \
  --argjson push_commits     "$NEW_PC" \
  --argjson max_issues_per_run "$NEW_MI" \
  '{preset: $preset, create_issues: $create_issues, create_prs: $create_prs, push_commits: $push_commits, max_issues_per_run: $max_issues_per_run}')

if gh api "repos/$REPO/actions/variables/AUTO_DEV_CONFIG" &>/dev/null 2>&1; then
  HTTP_METHOD="PATCH"; API_PATH="repos/$REPO/actions/variables/AUTO_DEV_CONFIG"
else
  HTTP_METHOD="POST";  API_PATH="repos/$REPO/actions/variables"
fi

echo ""
if gh api -X "$HTTP_METHOD" "$API_PATH" \
     -f name="AUTO_DEV_CONFIG" -f value="$NEW_CONFIG" >/dev/null 2>&1; then
  gum style --foreground 2 "✓ Config saved (preset: $PRESET)"
else
  gum style --foreground 1 "✗ Save failed — ensure gh has repo/actions write scope:"
  echo "  gh auth refresh -s repo"
fi
echo ""
