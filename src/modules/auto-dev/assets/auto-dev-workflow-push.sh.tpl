#!/usr/bin/env bash
# auto-dev-workflow-push.sh — Push latest auto-dev workflow files into a managed repo.
# Does NOT touch the runner registration.
#
# Always operates on a fresh shallow clone of the repo's DEFAULT branch, never the
# user's working checkout. auto-dev itself leaves ~/repos/<repo> on a task/* branch
# (often behind/dirty), so `git push origin HEAD` there would target the wrong branch
# or get rejected. The temp clone makes the update independent of local checkout state.
#
# Usage: auto-dev-workflow-push.sh <owner/repo>

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPTS_DIR="{{scripts_dir}}"
WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-cycle.yml"
LABEL_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-label.yml"
PM_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-pm.yml"
REBASE_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-rebase.yml"

REPO="${1:-}"
[[ -z "$REPO" ]] && exit 0

echo "Pushing workflows for $REPO"

DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef -q '.defaultBranchRef.name')
[[ -z "$DEFAULT_BRANCH" ]] && { echo "Error: could not determine default branch for $REPO"; exit 1; }
echo "  Default branch: $DEFAULT_BRANCH"

TEMP_CLONE=$(mktemp -d)
trap 'rm -rf "$TEMP_CLONE"' EXIT
echo "→ Cloning $DEFAULT_BRANCH into temp dir..."
gh repo clone "$REPO" "$TEMP_CLONE" -- --depth 1 --branch "$DEFAULT_BRANCH" --single-branch

WORKFLOW_DIR="$TEMP_CLONE/.github/workflows"
mkdir -p "$WORKFLOW_DIR"
cp "$WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-cycle.yml"
cp "$LABEL_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-label.yml"
cp "$PM_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-pm.yml"
cp "$REBASE_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-rebase.yml"

cd "$TEMP_CLONE"
git add .github/workflows/auto-dev-cycle.yml .github/workflows/auto-dev-label.yml .github/workflows/auto-dev-pm.yml .github/workflows/auto-dev-rebase.yml
if git diff --cached --quiet; then
  echo "  Workflows already up to date, no new commit needed."
else
  git commit -m "ci: update auto-dev workflows"
  echo "→ Pushing to $DEFAULT_BRANCH..."
  git push origin "HEAD:$DEFAULT_BRANCH"
  echo "  Workflows pushed."
fi

# ── Ensure GitHub Project board (idempotent, local gh auth) ──
# Fatal by design: surface a missing `project` scope rather than skipping silently.
echo "→ Ensuring GitHub Project board for $REPO..."
"$SCRIPTS_DIR/auto-dev-project-ensure.sh" "$REPO"

osascript -e "display notification \"Workflows pushed for $REPO\" with title \"Claude Toolkit\" subtitle \"Auto-dev Reinstall\"" 2>/dev/null || true
echo ""
echo "✓ Workflow push complete for $REPO"
