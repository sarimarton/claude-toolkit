#!/usr/bin/env bash
# auto-dev-runner-setup.sh — Install GitHub Actions self-hosted runner + workflow into a target repo
#
# Usage: auto-dev-runner-setup.sh <owner/repo> [local-path]
#
# What it does:
#   1. Gets a registration token via `gh api`
#   2. Downloads the GitHub Actions runner binary (if not already present)
#   3. Configures the runner for the target repo
#   4. Copies the workflow YAML into the repo's .github/workflows/
#   5. Commits and pushes the workflow
#   6. Prints instructions to start the runner

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPTS_DIR="{{scripts_dir}}"
HOME_DIR="{{home}}"
RUNNERS_DIR="$HOME_DIR/.config/claude-toolkit/runners"
WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-cycle.yml"
LABEL_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-label.yml"
PM_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-pm.yml"
REBASE_WORKFLOW_SRC="$SCRIPTS_DIR/auto-dev-rebase.yml"
STATE_DIR="$HOME_DIR/Documents/state/claude-toolkit/auto-dev"

# ── Args ──────────────────────────────────────────────
REPO="${1:-}"
LOCAL_PATH="${2:-}"

if [[ -z "$REPO" ]]; then
  JQ={{jq}}

  # Build repo list live (picker is rare; always fresh so new repos show up).
  # Candidates = repos WITHOUT the auto-dev topic, sorted case-insensitively.
  REPO_LIST=$(gh repo list --json nameWithOwner,repositoryTopics --limit 100 2>/dev/null \
    | $JQ -r '[.[] | select((.repositoryTopics // []) | map(.name) | contains(["auto-dev"]) | not) | .nameWithOwner] | sort_by(ascii_downcase) | .[]' 2>/dev/null)

  if [[ -n "$REPO_LIST" ]]; then
    # Build AppleScript list: {"owner/a", "owner/b", ...}
    AS_ITEMS=$(echo "$REPO_LIST" | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')
    REPO=$(osascript <<ASEOF 2>/dev/null
set repoList to {$AS_ITEMS}
set chosen to choose from list repoList with prompt "Install auto-dev into which repo?" with title "Auto-dev Setup" OK button name "Install" cancel button name "Cancel"
if chosen is false then return ""
return item 1 of chosen
ASEOF
    )
  else
    # No repos available — fall back to text input
    REPO=$(osascript -e 'text returned of (display dialog "Install auto-dev into which GitHub repo?" default answer "owner/repo" with title "Auto-dev Setup" buttons {"Cancel", "Install"} default button "Install")' 2>/dev/null)
    [[ "$REPO" == "owner/repo" ]] && REPO=""
  fi

  [[ -z "$REPO" ]] && exit 0
fi

REPO_SLUG="${REPO//\//-}"
RUNNER_DIR="$RUNNERS_DIR/$REPO_SLUG"

# ── Detect local path ──────────────────────────────────
TEMP_CLONE=""
if [[ -z "$LOCAL_PATH" ]]; then
  REPO_NAME="${REPO##*/}"
  LOCAL_PATH="$HOME_DIR/repos/$REPO_NAME"
fi

if [[ ! -d "$LOCAL_PATH" ]]; then
  TEMP_CLONE=$(mktemp -d)
  echo "→ Repo not found locally, cloning into temp dir..."
  gh repo clone "$REPO" "$TEMP_CLONE"
  LOCAL_PATH="$TEMP_CLONE"
fi

echo "Setting up auto-dev for $REPO"
echo "  Runner dir:  $RUNNER_DIR"
echo "  Local path:  $LOCAL_PATH"
echo ""

# ── Step 1: Registration token ────────────────────────
echo "→ Getting runner registration token..."
REG_TOKEN=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" 2>/dev/null | jq -r '.token' | head -n 1)
if [[ -z "$REG_TOKEN" ]]; then
  echo "Error: failed to get registration token. Is 'gh auth login' done and do you have admin access?"
  exit 1
fi

# ── Step 2: Download runner binary ────────────────────
mkdir -p "$RUNNER_DIR"
echo "$REPO" > "$RUNNER_DIR/.repo-name"

if [[ ! -f "$RUNNER_DIR/run.sh" ]]; then
  echo "→ Downloading GitHub Actions runner..."
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" ]]; then
    RUNNER_ARCH="arm64"
  else
    RUNNER_ARCH="x64"
  fi

  LATEST=$(gh api /repos/actions/runner/releases/latest 2>/dev/null | jq -r '.tag_name' | head -n 1 | tr -d 'v')
  RUNNER_PKG="actions-runner-osx-${RUNNER_ARCH}-${LATEST}.tar.gz"
  RUNNER_URL="https://github.com/actions/runner/releases/download/v${LATEST}/${RUNNER_PKG}"

  curl -fsSL -o "/tmp/$RUNNER_PKG" "$RUNNER_URL"
  tar xzf "/tmp/$RUNNER_PKG" -C "$RUNNER_DIR"
  rm "/tmp/$RUNNER_PKG"
  echo "  Runner binary installed at $RUNNER_DIR"
else
  echo "→ Runner binary already present at $RUNNER_DIR"
fi

# ── Step 3: Configure runner ──────────────────────────
echo "→ Configuring runner..."
RUNNER_NAME="auto-dev-$(hostname -s)-$REPO_SLUG"

# Remove existing config if present (allows re-registration)
if [[ -f "$RUNNER_DIR/.runner" ]]; then
  "$RUNNER_DIR/config.sh" remove --token "$REG_TOKEN" 2>/dev/null || true
fi

"$RUNNER_DIR/config.sh" \
  --url "https://github.com/$REPO" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "self-hosted,macOS" \
  --work "$RUNNER_DIR/_work" \
  --unattended \
  --replace

echo "  Runner configured: $RUNNER_NAME"

# ── Step 4: Install workflows ─────────────────────────
echo "→ Installing workflows into $REPO..."
WORKFLOW_DIR="$LOCAL_PATH/.github/workflows"
mkdir -p "$WORKFLOW_DIR"
cp "$WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-cycle.yml"
cp "$LABEL_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-label.yml"
cp "$PM_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-pm.yml"
cp "$REBASE_WORKFLOW_SRC" "$WORKFLOW_DIR/auto-dev-rebase.yml"

# ── Step 5: Commit and push workflows ─────────────────
echo "→ Committing workflows..."
cd "$LOCAL_PATH"
git add .github/workflows/auto-dev-cycle.yml .github/workflows/auto-dev-label.yml .github/workflows/auto-dev-pm.yml .github/workflows/auto-dev-rebase.yml
if git diff --cached --quiet; then
  echo "  Workflows already up to date, no new commit needed."
else
  git commit -m "ci: add auto-dev workflows"
  echo "  Workflows committed."
fi
echo "→ Pushing workflow..."
git push origin HEAD

# ── Cleanup temp clone ────────────────────────────────
if [[ -n "$TEMP_CLONE" ]]; then
  rm -rf "$TEMP_CLONE"
fi

# ── Step 6: Ensure state dir exists ───────────────────
mkdir -p "$STATE_DIR"

# ── Step 7: Tag repo with auto-dev topic ──────────────
echo "→ Adding 'auto-dev' topic to $REPO..."
if gh repo edit "$REPO" --add-topic auto-dev 2>/dev/null; then
  # Invalidate the menu's managed-repo cache (1h TTL) so the new repo appears on
  # the next render (~10s) instead of being hidden until the cache expires.
  rm -f /tmp/claude-toolkit-auto-dev-managed.json
  echo "  Topic added. The repo will appear in the Claude menu within ~10s."
else
  echo "  Warning: could not add topic (non-fatal)."
fi

# ── Step 8: Ensure GitHub Project board (idempotent, local gh auth) ──
# Fatal by design: if it fails (e.g. missing `project` scope) the setup must stop
# loudly rather than silently leave the repo without a board.
echo "→ Ensuring GitHub Project board for $REPO..."
"$SCRIPTS_DIR/auto-dev-project-ensure.sh" "$REPO"

# ── Done ──────────────────────────────────────────────
osascript -e "display notification \"auto-dev installed in $REPO. Runner: auto-dev-runner-control.sh start $REPO\" with title \"Claude Toolkit\" subtitle \"Auto-dev Setup Complete\"" 2>/dev/null || true
echo ""
echo "✓ Setup complete for $REPO"
echo ""
echo "To start the runner, run:"
echo "  auto-dev-runner-control.sh start $REPO"
echo ""
echo "Or start it directly:"
echo "  tmux new-session -d -s 'auto-dev-$REPO_SLUG' -c '$RUNNER_DIR' './run.sh'"
