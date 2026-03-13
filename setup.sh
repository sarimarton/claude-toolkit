#!/bin/sh
# Claude Toolkit — installer
#
# Remote install:  curl -fsSL https://raw.githubusercontent.com/sarimarton/claude-toolkit/main/setup.sh | sh
# Local install:   ./setup.sh           (from a cloned repo)
# Custom location: CLAUDE_TOOLKIT_DIR=~/my/path ./setup.sh
set -e

CONFIG_DIR="$HOME/.config/claude-toolkit"
BIN_DIR="$HOME/.local/bin"

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
  # Running locally (./setup.sh from the repo)
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

# ── VS Code Terminal Topic extension ─────────────────────

EXT_DIR="$INSTALL_DIR/src/modules/vscode-terminal-topic/extension"
if [ -d "$EXT_DIR" ] && command -v code >/dev/null 2>&1; then
  echo "Building VS Code Terminal Topic extension..."
  (cd "$EXT_DIR" && npm ci --ignore-scripts && npm run compile)
  if command -v vsce >/dev/null 2>&1; then
    (cd "$EXT_DIR" && vsce package -o "$EXT_DIR/vscode-terminal-topic.vsix" && code --install-extension "$EXT_DIR/vscode-terminal-topic.vsix" --force)
    echo "✓ VS Code Terminal Topic extension installed"
  else
    # Fallback: direct copy to extensions dir
    VSCODE_EXT_DIR="$HOME/.vscode/extensions/sarim.vscode-terminal-topic-0.1.0"
    mkdir -p "$VSCODE_EXT_DIR/out"
    cp "$EXT_DIR/package.json" "$VSCODE_EXT_DIR/"
    cp "$EXT_DIR/out/extension.js" "$VSCODE_EXT_DIR/out/"
    cp "$EXT_DIR/out/extension.js.map" "$VSCODE_EXT_DIR/out/" 2>/dev/null || true
    echo "✓ VS Code Terminal Topic extension installed (direct copy)"
  fi
fi

# ── Done ──────────────────────────────────────────────────

echo ""
echo "✓ Claude Toolkit installed!"
echo ""
echo "Make sure $BIN_DIR is in your PATH, then:"
echo "  claude-toolkit              # Interactive dashboard"
echo "  claude-toolkit list         # List available modules"
echo "  claude-toolkit install all  # Install all modules"
echo "  claude-toolkit doctor       # Health check"
