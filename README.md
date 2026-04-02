# Claude Toolkit

Modular session management toolkit for Claude Code — hooks, tmux integration, SwiftBar menubar, usage monitor, and more.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/sarimarton/claude-toolkit/main/setup.sh | sh
```

This clones the repo, builds, and launches the interactive module installer. Select modules with `space`, install with `i`.

## Update

```bash
claude-toolkit upgrade
```

This re-renders all installed module templates from the latest source. If the repo itself needs updating:

```bash
cd ~/.local/share/claude-toolkit && git pull && npm ci && npm run build
claude-toolkit upgrade
```

## Uninstall

```bash
claude-toolkit uninstall            # Dashboard — select modules, press 'u'
claude-toolkit uninstall <module>   # Remove specific module(s)
claude-toolkit uninstall all        # Remove all modules
```

To remove the entire toolkit:

```bash
claude-toolkit uninstall $(claude-toolkit list 2>/dev/null | grep -oE '✓ \S+|◐ \S+' | awk '{print $2}' | tr '\n' ' ')
rm -rf ~/.local/share/claude-toolkit ~/.config/claude-toolkit
rm -f ~/.local/bin/claude-toolkit
```

## Configuration

`~/.config/claude-toolkit/config.yaml`:

```yaml
# Override auto-detected paths
# paths:
#   tmux: /opt/homebrew/bin/tmux
#   claude: ~/.local/bin/claude

# Usage chart cost estimation
chart:
  planMonthlyCost: 150
  apiCostPerSessionPct: 0.20

# Multi-account usage monitoring
accounts:
  - name: Alice
    token: sk-ant-oat01-...
    primary: true
  - name: Bob
    token: sk-ant-oat01-...
```

**When to upgrade after config changes:**
- `accounts` — read at runtime, no upgrade needed
- `chart.*`, `paths.*` — baked at install time, run `claude-toolkit upgrade`

## Usage

```bash
claude-toolkit                  # Interactive dashboard (j/k, space, i/u)
claude-toolkit list             # List all modules with status
claude-toolkit install <mod..>  # Install modules (auto-resolves dependencies)
claude-toolkit uninstall <mod.> # Uninstall modules (cascade warning)
claude-toolkit status           # Detailed per-module health check
claude-toolkit doctor           # Full integrity audit
claude-toolkit upgrade          # Re-template installed modules
claude-toolkit chart            # Open usage chart dashboard in browser
```

## Modules

| Module | Platform | Description |
|---|---|---|
| **topic-markers** | any | `$topic` / `$completeness` / `$state` markers on every response |
| **tmux-titles** | any | Sets tmux window name from topic marker |
| **tmux-sessions** | any | AI session aggregator (`ts` command + `/tmux` slash command) |
| **usage-monitor** | any | Polls `/usage` via dedicated tmux session → JSON + JSONL log |
| **menubar** | macOS | SwiftBar plugin: usage %, sessions, focus/attach/kill |
| **notifications** | macOS | Desktop notifications via terminal-notifier |
| **sounds** | macOS | Sound effects on tool use and stop events |
| **stt-recovery** | any | Hungarian speech-to-text correction (two-phase LLM) |
| **ghostty-tmux** | any | Ghostty tab command with session lifecycle management |
| **vscode-tmux** | any | VS Code terminal profile with tmux integration |
| **vscode-terminal-topic** | macOS | VS Code extension: terminal tab renaming from $topic markers |

### Dependency graph

```
topic-markers ← tmux-titles
              ← tmux-sessions ← menubar
                                 ↑
usage-monitor ───────────────────┘

notifications, sounds, stt-recovery, ghostty-tmux, vscode-tmux — independent
```

## How it works

1. **Templates**: Every script lives as a `.sh.tpl` file with `{{var}}` placeholders (paths, binaries)
2. **Install**: Template engine renders scripts → `~/.config/claude-toolkit/{hooks,scripts,commands,swiftbar}/`
3. **Hooks**: Registered in `~/.claude/settings.json` (idempotent — deduped on reinstall)
4. **Sidecar**: `~/.claude/.claude-toolkit-manifest.json` tracks which hooks belong to which module
5. **Uninstall**: Sidecar-based removal — only deletes its own hooks, leaves user hooks intact

## Development

```bash
npm install
npm run build          # tsc + copy assets to dist/
npm run dev -- list    # run via tsx (no build needed)
```
