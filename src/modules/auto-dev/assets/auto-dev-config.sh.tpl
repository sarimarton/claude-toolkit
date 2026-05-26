#!/usr/bin/env bash
# auto-dev-config.sh — Edit per-repo auto-dev autonomy via gum TUI.
# Config is stored as JSON in a GitHub Actions repo variable: AUTO_DEV_CONFIG
# Only field: {"autonomy": "high" | "low"}
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
CURRENT=$(echo "$RAW" | $JQ -r '.autonomy // "high"' 2>/dev/null || echo "high")

# ── Header ────────────────────────────────────────────────────
echo ""
gum style \
  --border rounded --border-foreground 212 \
  --padding "0 2" --bold \
  "Auto-dev Config: $REPO"
echo ""
gum style --foreground 244 "high: opens issues + PRs + pushes commits autonomously"
gum style --foreground 244 "low:  opens issues + comments only (no PRs, no pushes)"
echo ""

# ── Autonomy selection ────────────────────────────────────────
AUTONOMY=$(gum choose \
  --header "Autonomy level:" \
  --selected "$CURRENT" \
  "high" "low")
[[ -z "$AUTONOMY" ]] && exit 0

# ── Confirm ───────────────────────────────────────────────────
echo ""
gum confirm "Save autonomy=$AUTONOMY for $REPO?" || exit 0

# ── Build and write config ────────────────────────────────────
NEW_CONFIG=$($JQ -nc --arg a "$AUTONOMY" '{autonomy: $a}')

if gh api "repos/$REPO/actions/variables/AUTO_DEV_CONFIG" &>/dev/null 2>&1; then
  HTTP_METHOD="PATCH"; API_PATH="repos/$REPO/actions/variables/AUTO_DEV_CONFIG"
else
  HTTP_METHOD="POST";  API_PATH="repos/$REPO/actions/variables"
fi

echo ""
if gh api -X "$HTTP_METHOD" "$API_PATH" \
     -f name="AUTO_DEV_CONFIG" -f value="$NEW_CONFIG" >/dev/null 2>&1; then
  gum style --foreground 2 "✓ Config saved (autonomy: $AUTONOMY)"
else
  gum style --foreground 1 "✗ Save failed — ensure gh has repo/actions write scope:"
  echo "  gh auth refresh -s repo"
fi
echo ""
