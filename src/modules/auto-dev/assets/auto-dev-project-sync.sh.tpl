#!/usr/bin/env bash
# auto-dev-project-sync.sh — Mirror ONE issue's auto-dev state onto its repo's
# GitHub Projects V2 board. The board is a READ-ONLY mirror: the ai:* labels are
# the single source of truth, this only writes the board's Status field.
#
# Runs on the self-hosted runner (same machine as the user's gh login). The runner's
# default GITHUB_TOKEN cannot reach Projects V2, so every board call strips the token
# (`env -u GH_TOKEN`) to fall back to the machine's stored gh auth, which carries the
# `project` scope. gh token precedence is GH_TOKEN > GITHUB_TOKEN > stored creds, and
# the cycle workflow only ever sets GH_TOKEN — so unsetting GH_TOKEN alone is enough
# (unsetting GITHUB_TOKEN too would be dead redundancy).
#
# Add-only + one-way: never removes board items, never touches issues/labels/PRs.
# Idempotent and self-healing — each cycle re-derives Status from current labels, so
# a sync missed during a crash is repaired on the next run. Every failure is non-fatal
# (exit 0) so board sync can never break the development cycle.
#
# Usage: auto-dev-project-sync.sh <owner/repo> <issue-number>

set -uo pipefail
export PATH="{{home}}/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

JQ={{jq}}
HOME_DIR="{{home}}"
PROJECTS_STATE="$HOME_DIR/Documents/state/claude-toolkit/auto-dev/auto-dev-projects.json"

REPO="${1:-}"
ISSUE="${2:-}"
[[ -z "$REPO" || -z "$ISSUE" ]] && { echo "Usage: $0 <owner/repo> <issue-number>"; exit 0; }
OWNER="${REPO%%/*}"

# gh under the machine's stored auth (project scope), NOT the runner GITHUB_TOKEN.
ghp() { env -u GH_TOKEN gh "$@"; }

# ── Resolve the board from the ensure-written mapping ─────────────────
[[ -f "$PROJECTS_STATE" ]] || { echo "No projects state — skipping board sync (run project-ensure first)"; exit 0; }
PROJECT_NUMBER=$($JQ -r --arg r "$REPO" '.[$r].number // empty' "$PROJECTS_STATE")
[[ -z "$PROJECT_NUMBER" ]] && { echo "No board mapped for $REPO — skipping board sync"; exit 0; }

# ── Read the issue's CURRENT labels/state → dominant Status ───────────
# (labels are truth; this mirrors them, never the other way around)
ISSUE_JSON=$(ghp issue view "$ISSUE" --repo "$REPO" --json labels,state,url 2>/dev/null)
[[ -z "$ISSUE_JSON" ]] && { echo "Cannot read issue #$ISSUE — skipping board sync"; exit 0; }
NAMES=$(echo "$ISSUE_JSON" | $JQ -c '[.labels[].name]')
ISSUE_STATE=$(echo "$ISSUE_JSON" | $JQ -r '.state')
ISSUE_URL=$(echo "$ISSUE_JSON" | $JQ -r '.url')
has() { echo "$NAMES" | $JQ -e --arg n "$1" 'index($n)' >/dev/null 2>&1; }

if   [[ "$ISSUE_STATE" == "CLOSED" ]]; then STATUS="Done"
elif has "ai:epic";        then STATUS="Epic"
elif has "ai:blocked";     then STATUS="Blocked"
elif has "ai:done";        then STATUS="Done"
elif has "ai:in-progress"; then STATUS="In progress"
elif has "ai:ready";       then STATUS="Ready"
elif has "ai:clarifying";  then STATUS="Clarifying"
elif has "ai";             then STATUS="New"
else echo "Issue #$ISSUE has no ai* label — nothing to mirror"; exit 0
fi

# ── Ensure the issue is an item on the board (idempotent) ─────────────
ITEM_ID=$(ghp project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json --limit 1000 2>/dev/null \
  | $JQ -r --argjson n "$ISSUE" 'first(.items[]? | select(.content.type == "Issue" and .content.number == $n) | .id) // empty')
if [[ -z "$ITEM_ID" ]]; then
  ITEM_ID=$(ghp project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$ISSUE_URL" --format json 2>/dev/null \
    | $JQ -r '.id // empty')
fi
[[ -z "$ITEM_ID" ]] && { echo "Could not add/find board item for #$ISSUE — skipping"; exit 0; }

# ── Set the Status single-select to match the derived state ───────────
FIELDS=$(ghp project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null)
STATUS_FIELD_ID=$(echo "$FIELDS" | $JQ -r 'first(.fields[]? | select(.name == "Status") | .id) // empty')
OPTION_ID=$(echo "$FIELDS" | $JQ -r --arg s "$STATUS" \
  'first(.fields[]? | select(.name == "Status") | .options[]? | select(.name == $s) | .id) // empty')
PROJECT_ID=$(ghp project view "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null | $JQ -r '.id // empty')

if [[ -n "$STATUS_FIELD_ID" && -n "$OPTION_ID" && -n "$PROJECT_ID" ]]; then
  if ghp project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" \
       --field-id "$STATUS_FIELD_ID" --single-select-option-id "$OPTION_ID" >/dev/null 2>&1; then
    echo "✓ #$ISSUE → $STATUS"
  else
    echo "(Could not set Status for #$ISSUE — non-fatal)"
  fi
else
  echo "(Status field/option '$STATUS' not found on board — skipping, non-fatal)"
fi

exit 0
