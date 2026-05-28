#!/usr/bin/env bash
# auto-dev-workflow-push.sh — Push latest auto-dev workflow files into a managed repo.
# Does NOT touch the runner registration.
#
# Usage: auto-dev-workflow-push.sh <owner/repo>

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPTS_DIR="{{scripts_dir}}"
HOME_DIR="{{home}}"
WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-cycle.yml"
LABEL_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-label.yml"
PM_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-pm.yml"
REBASE_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-rebase.yml"

REPO="${1:-}"
[[ -z "$REPO" ]] && exit 0

LOCAL_PATH="$HOME_DIR/repos/${REPO##*/}"

TEMP_CLONE=""
if [[ ! -d "$LOCAL_PATH" ]]; then
  TEMP_CLONE=$(mktemp -d)
  echo "→ Repo not found locally, cloning into temp dir..."
  gh repo clone "$REPO" "$TEMP_CLONE"
  LOCAL_PATH="$TEMP_CLONE"
fi

echo "Pushing workflows for $REPO"
echo "  Local path: $LOCAL_PATH"
echo ""

WORKFLOW_DIR="$LOCAL_PATH/.github/workflows"
mkdir -p "$WORKFLOW_DIR"
cp "$WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-cycle.yml"
cp "$LABEL_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-label.yml"
cp "$PM_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-pm.yml"
cp "$REBASE_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-rebase.yml"

cd "$LOCAL_PATH"
git add .github/workflows/auto-dev-cycle.yml .github/workflows/auto-dev-label.yml .github/workflows/auto-dev-pm.yml .github/workflows/auto-dev-rebase.yml
if git diff --cached --quiet; then
  echo "  Workflows already up to date, no new commit needed."
else
  git commit -m "ci: update auto-dev workflows"
  echo "  Workflows committed."
fi
echo "→ Pushing..."
git push origin HEAD

[[ -n "$TEMP_CLONE" ]] && rm -rf "$TEMP_CLONE"

# ── Ensure GitHub Project board (idempotent, local gh auth) ──
# Fatal by design: surface a missing `project` scope rather than skipping silently.
echo "→ Ensuring GitHub Project board for $REPO..."
"$SCRIPTS_DIR/auto-dev-project-ensure.sh" "$REPO"

osascript -e "display notification \"Workflows pushed for $REPO\" with title \"Claude Toolkit\" subtitle \"Auto-dev Reinstall\"" 2>/dev/null || true
echo ""
echo "✓ Workflow push complete for $REPO"
