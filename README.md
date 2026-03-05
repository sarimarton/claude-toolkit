# Claude Toolkit

Modular session management toolkit for Claude Code — hooks, tmux integration, SwiftBar menubar, usage monitor, and more.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/sarimarton/claude-toolkit/main/setup.sh | sh
```

## Usage

```bash
claude-toolkit                  # Interactive dashboard (j/k, space, i/u)
claude-toolkit list             # List all modules with status
claude-toolkit install <mod..>  # Install modules (auto-resolves dependencies)
claude-toolkit uninstall <mod.> # Uninstall modules (cascade warning)
claude-toolkit status           # Detailed per-module health check
claude-toolkit doctor           # Full integrity audit
claude-toolkit upgrade          # Re-template installed modules (after path changes)
```

## Modules

| Module | Platform | Description |
|---|---|---|
| **topic-markers** | any | `$topic` / `$completeness` / `$state` markers on every response |
| **tmux-titles** | any | Sets tmux window name from topic marker |
| **tmux-sessions** | any | AI session aggregator (`ts` command + `/tmux` slash command) |
| **usage-monitor** | any | Polls `/usage` via dedicated tmux session → JSON |
| **menubar** | macOS | SwiftBar plugin: usage %, sessions, focus/attach/kill |
| **notifications** | macOS | Desktop notifications via terminal-notifier |
| **sounds** | macOS | Sound effects on tool use and stop events |
| **stt-recovery** | any | Hungarian speech-to-text correction (two-phase LLM) |
| **ghostty-tmux** | any | Ghostty tab command with session lifecycle management |
| **vscode-tmux** | any | VS Code terminal profile with tmux integration |

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
3. **Hooks**: Registered in `~/.claude/settings.json` (append-only, never touches non-hook settings)
4. **Sidecar**: `~/.claude/.claude-toolkit-manifest.json` tracks which hooks belong to which module
5. **Uninstall**: Sidecar-based removal — only deletes its own hooks, leaves user hooks intact

## Configuration

`~/.config/claude-toolkit/config.yaml` — override auto-detected paths:

```yaml
# paths:
#   tmux: /opt/homebrew/bin/tmux
#   claude: ~/.local/bin/claude
```

## Development

```bash
npm install
npm run build          # tsc + copy assets to dist/
npm run dev -- list    # run via tsx (no build needed)
```
