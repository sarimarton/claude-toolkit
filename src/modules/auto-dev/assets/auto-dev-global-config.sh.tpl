#!/usr/bin/env bash
# auto-dev-global-config.sh — Edit machine-global auto-dev settings via gum TUI.
# Config is stored locally at ~/.config/claude-toolkit/global.json
# Fields: {"max_issues_per_run": N, "bailout_pct": N}
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

# ── If not in a terminal, relaunch self in Terminal.app ───────
if [ ! -t 0 ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  osascript \
    -e 'tell application "Terminal"' \
    -e '  activate' \
    -e "  do script \"'$SELF'; echo ''; read -p 'Press Enter to close...'\"" \
    -e 'end tell'
  exit 0
fi

JQ={{jq}}
CONFIG_FILE="{{home}}/.config/claude-toolkit/global.json"
mkdir -p "$(dirname "$CONFIG_FILE")"

# ── Ensure gum is installed ───────────────────────────────────
if ! command -v gum &>/dev/null; then
  echo "Installing gum..."
  brew install gum
fi

# ── Read current config ───────────────────────────────────────
if [[ -f "$CONFIG_FILE" ]]; then
  CONFIG=$(cat "$CONFIG_FILE")
else
  CONFIG='{}'
fi
CURR_MI=$(echo "$CONFIG" | $JQ -r '.max_issues_per_run // 3')
CURR_BP=$(echo "$CONFIG" | $JQ -r '.bailout_pct // 50')

# ── Header ────────────────────────────────────────────────────
echo ""
gum style \
  --border rounded --border-foreground 212 \
  --padding "0 2" --bold \
  "Auto-dev Global Config"
echo ""
gum style --foreground 244 "These settings apply to all auto-dev runners on this machine."
echo ""

# ── max_issues_per_run ────────────────────────────────────────
gum style "max_issues_per_run — Max issues per scheduled run (1–20):"
NEW_MI=$(gum input --value "$CURR_MI" --placeholder "1-20")
[[ -z "$NEW_MI" ]] && exit 0
if ! [[ "$NEW_MI" =~ ^[0-9]+$ ]] || (( NEW_MI < 1 || NEW_MI > 20 )); then
  gum style --foreground 1 "✗ max_issues_per_run must be a number between 1 and 20"
  exit 1
fi

# ── bailout_pct ───────────────────────────────────────────────
echo ""
gum style "bailout_pct — Skip run if Claude usage is at or above this % (0–100):"
NEW_BP=$(gum input --value "$CURR_BP" --placeholder "0-100")
[[ -z "$NEW_BP" ]] && exit 0
if ! [[ "$NEW_BP" =~ ^[0-9]+$ ]] || (( NEW_BP < 0 || NEW_BP > 100 )); then
  gum style --foreground 1 "✗ bailout_pct must be a number between 0 and 100"
  exit 1
fi

# ── Confirm ───────────────────────────────────────────────────
echo ""
gum confirm "Save global config?" || exit 0

# ── Write config ──────────────────────────────────────────────
$JQ -n \
  --argjson mi "$NEW_MI" \
  --argjson bp "$NEW_BP" \
  '{max_issues_per_run: $mi, bailout_pct: $bp}' > "$CONFIG_FILE"

echo ""
gum style --foreground 2 "✓ Global config saved to $CONFIG_FILE"
echo ""
