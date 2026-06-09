#!/bin/sh
# Claude Toolkit — installer
#
# Remote install:  curl -fsSL https://raw.githubusercontent.com/sarimarton/claude-toolkit/main/setup.sh | sh
# Local install:   ./setup.sh           (from a cloned repo)
# Custom location: CLAUDE_TOOLKIT_DIR=~/my/path ./setup.sh
set -e

CONFIG_DIR="$HOME/.config/claude-toolkit"
BIN_DIR="$HOME/.local/bin"
CANONICAL_DEPLOY_DIR="$HOME/.local/share/claude-toolkit"

# Detect --yes/-y so the deploy-target guard can be skipped non-interactively.
ASSUME_YES=false
for _arg in "$@"; do
  case "$_arg" in
    --yes|-y) ASSUME_YES=true ;;
  esac
done

# Decision logic for the deploy-target guard lives in setup-guard.sh (unit-tested).
GUARD_LIB="$(cd "$(dirname "$0")" && pwd)/setup-guard.sh"
[ -f "$GUARD_LIB" ] && . "$GUARD_LIB"

echo "Claude Toolkit — Setup"
echo "======================"
echo ""

# ── Prerequisites ─────────────────────────────────────────

check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: $1 is required but not found."
    [ -n "$2" ] && echo "  Install: $2"
    exit 1
  fi
}

check_cmd node "https://nodejs.org or: brew install node"
check_cmd git
check_cmd jq "brew install jq"

# Check node version >= 20
NODE_MAJOR=$(node -e 'console.log(process.versions.node.split(".")[0])')
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "Error: Node.js >= 20 required (found v$(node -v))"
  exit 1
fi

echo "✓ Prerequisites OK (node v$(node -v | tr -d v), git, jq)"

# ── Locate or clone the repo ─────────────────────────────

# Detect if we're running from inside a cloned repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/package.json" ] && grep -q '"claude-toolkit"' "$SCRIPT_DIR/package.json" 2>/dev/null; then
  # Running locally (./setup.sh from the repo). Guard against the "dev clone
  # becomes deploy target" trap: if SCRIPT_DIR isn't the canonical deploy dir and
  # the user hasn't opted in (CLAUDE_TOOLKIT_DIR / --yes), confirm first —
  # otherwise `claude-toolkit update` would git-reset --hard this working tree.
  if command -v needs_deploy_target_confirmation >/dev/null 2>&1 \
     && needs_deploy_target_confirmation "$SCRIPT_DIR" "$CANONICAL_DEPLOY_DIR" "${CLAUDE_TOOLKIT_DIR:-}" "$ASSUME_YES"; then
    echo "⚠  About to use '$SCRIPT_DIR' as the deploy target (install dir)."
    echo "   This looks like a development clone, not the canonical deploy location"
    echo "   ($CANONICAL_DEPLOY_DIR). Installing here wires this working tree as the"
    echo "   deploy target, so 'claude-toolkit update' will 'git reset --hard' it."
    echo ""
    echo "   To deploy separately instead, re-run from outside the repo (curl | sh)"
    echo "   or set CLAUDE_TOOLKIT_DIR=$CANONICAL_DEPLOY_DIR explicitly."
    echo ""
    if [ -t 0 ]; then
      printf "   Continue using this dir as the deploy target? [y/N] "
      read -r _reply </dev/tty
      case "$_reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted."; exit 1 ;;
      esac
    else
      echo "   Non-interactive (no TTY); aborting. Pass --yes to override."
      exit 1
    fi
  fi
  INSTALL_DIR="${CLAUDE_TOOLKIT_DIR:-$SCRIPT_DIR}"
  echo "Using local repo: $INSTALL_DIR"
  cd "$INSTALL_DIR"
else
  # Running via curl | sh or from outside the repo — need to clone
  INSTALL_DIR="${CLAUDE_TOOLKIT_DIR:-$HOME/.local/share/claude-toolkit}"
  REPO_URL="${CLAUDE_TOOLKIT_REPO:-https://github.com/sarimarton/claude-toolkit.git}"
  if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull --ff-only
  else
    echo "Cloning to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi
fi

# ── Build ─────────────────────────────────────────────────

echo "Installing dependencies..."
npm ci --ignore-scripts

echo "Building..."
npm run build

# ── Symlink ───────────────────────────────────────────────

mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/dist/cli.js" "$BIN_DIR/claude-toolkit"
chmod +x "$BIN_DIR/claude-toolkit"

# ── Config ────────────────────────────────────────────────

mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/topics"
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
  cp "$INSTALL_DIR/config.default.yaml" "$CONFIG_DIR/config.yaml"
  echo "Created $CONFIG_DIR/config.yaml"
fi

# ── PATH ──────────────────────────────────────────────────

# Add BIN_DIR to PATH in shell rc files if not already there
add_to_path() {
  local rc="$1"
  if [ -f "$rc" ] && ! grep -q "$BIN_DIR" "$rc" 2>/dev/null; then
    printf '\n# Added by claude-toolkit\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$rc"
    echo "Added $BIN_DIR to PATH in $rc"
  fi
}

case "$SHELL" in
  */zsh)  add_to_path "$HOME/.zshrc" ;;
  */bash) add_to_path "$HOME/.bashrc"; add_to_path "$HOME/.bash_profile" ;;
  *)      add_to_path "$HOME/.profile" ;;
esac

# Also export for the current process so the TUI launch below works
export PATH="$BIN_DIR:$PATH"

# ── Done ──────────────────────────────────────────────────

echo ""
echo "✓ Claude Toolkit installed!"
echo ""
# Launch interactive dashboard if stdout is a terminal
if [ -t 1 ]; then
  echo "Launching module installer..."
  echo ""
  # Reopen stdin from /dev/tty so the TUI works even when script is piped (curl | sh)
  "$BIN_DIR/claude-toolkit" </dev/tty
else
  echo "Make sure $BIN_DIR is in your PATH, then:"
  echo "  claude-toolkit              # Interactive dashboard"
  echo "  claude-toolkit list         # List available modules"
  echo "  claude-toolkit install all  # Install all modules"
  echo "  claude-toolkit doctor       # Health check"
fi
