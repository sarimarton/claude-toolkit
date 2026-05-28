#!/usr/bin/env bash
# auto-dev-project-ensure.sh — Idempotently ensure a GitHub Projects V2 board exists
# for a managed auto-dev repo, linked to that repo, with an ai:*-aligned Status field.
#
# Runs LOCALLY under the user's gh auth (which carries the `project` scope) — this is
# NOT meant to run on the self-hosted runner, whose GITHUB_TOKEN cannot reach user/org
# Projects V2. Called from install (runner-setup) and update (workflow-push).
#
# Safe to re-run: it creates nothing that already exists. Exits non-zero (fatal) if
# gh lacks the `project` scope, so the caller surfaces the misconfiguration.
#
# Usage: auto-dev-project-ensure.sh <owner/repo>

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:{{home}}/.local/bin:/usr/bin:/bin:$PATH"

JQ={{jq}}
HOME_DIR="{{home}}"
STATE_DIR="$HOME_DIR/Documents/state/claude-toolkit/auto-dev"
PROJECTS_STATE="$STATE_DIR/auto-dev-projects.json"

REPO="${1:-}"
[[ -z "$REPO" ]] && { echo "Usage: $0 <owner/repo>"; exit 1; }

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
TITLE="Auto-dev: $NAME"

mkdir -p "$STATE_DIR"
[[ -f "$PROJECTS_STATE" ]] || echo '{}' > "$PROJECTS_STATE"

# ── Verify gh can actually reach Projects (scope check) ───────────────
# Projects V2 is owner-scoped; a missing `project` scope is the common failure.
# This is FATAL on purpose: a silent skip would hide the misconfiguration.
if ! gh project list --owner "$OWNER" --limit 1 >/dev/null 2>&1; then
  echo "✗ ERROR: gh cannot access Projects for '$OWNER' (missing 'project' scope?)." >&2
  echo "  Grant it once, then re-run:  gh auth refresh -s project,read:project" >&2
  exit 1
fi

# ── Find existing project by title (idempotency key) ──────────────────
PROJECT_NUMBER=$(gh project list --owner "$OWNER" --format json --limit 100 2>/dev/null \
  | $JQ -r --arg t "$TITLE" '.projects[]? | select(.title == $t) | .number' | head -n1)

if [[ -z "$PROJECT_NUMBER" ]]; then
  echo "→ Creating project '$TITLE' under $OWNER..."
  PROJECT_NUMBER=$(gh project create --owner "$OWNER" --title "$TITLE" --format json 2>/dev/null | $JQ -r '.number')
  if [[ -z "$PROJECT_NUMBER" || "$PROJECT_NUMBER" == "null" ]]; then
    echo "Error: project create failed."; exit 1
  fi
  echo "  Created project #$PROJECT_NUMBER"
else
  echo "→ Project '$TITLE' already exists (#$PROJECT_NUMBER)"
fi

# ── Link project to the repo (shows under the repo's Projects tab) ────
# Idempotent: linking an already-linked project is a harmless no-op error.
gh project link "$PROJECT_NUMBER" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 || true

# ── Ensure a Status single-select field aligned with the ai:* states ──
# A project created via the API usually has no Status field yet; if one already
# exists (built-in or ours) we leave it untouched to stay idempotent.
HAS_STATUS=$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null \
  | $JQ -r '[.fields[]? | select(.name == "Status")] | length')
if [[ "${HAS_STATUS:-0}" == "0" ]]; then
  echo "→ Creating Status field (New / Clarifying / Ready / In progress / Done / Blocked / Epic)..."
  if gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
      --name "Status" --data-type SINGLE_SELECT \
      --single-select-options "New,Clarifying,Ready,In progress,Done,Blocked,Epic" >/dev/null 2>&1; then
    echo "  Status field created"
  else
    echo "  (Could not create Status field — a Status field may already exist; non-fatal)"
  fi
fi

# ── Persist the repo→project mapping for the (future) runner-side sync ─
PROJECT_URL=$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null | $JQ -r '.url // ""')
TMP=$(mktemp)
$JQ --arg repo "$REPO" --arg owner "$OWNER" --argjson num "$PROJECT_NUMBER" --arg url "$PROJECT_URL" \
  '.[$repo] = {owner: $owner, number: $num, url: $url}' "$PROJECTS_STATE" > "$TMP" && mv "$TMP" "$PROJECTS_STATE"

echo "✓ Project ready: ${PROJECT_URL:-#$PROJECT_NUMBER}"
