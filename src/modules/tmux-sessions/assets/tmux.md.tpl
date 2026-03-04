---
model: haiku
---

Orchestrate multiple Claude Code sessions running in tmux windows.

## Step 1 — Scan

Run this command to get the current state of all tmux panes:

```bash
{{scripts_dir}}/tmux-scan.sh
```

## Step 2 — Output

Print one line per pane. No markdown formatting, no bold, no headers,
no introduction, no summary. Plain text only.

Fixed 6-field format for EVERY line:

`pane_id; process; dir; topic; completeness; state`

- **pane_id**: from `PANE:` line (e.g. `vscode_-config:2`)
- **process**: from `[proc_type]` tag (e.g. `claude`, `zsh`, `node`)
- **dir**: working directory from `PANE:` line (e.g. `~/.config`, `~/repos/neobank-workspace`)
- **topic**: what this pane is about (5-10 words)
- **completeness**: task progress 0-100 (or `-` if not applicable)
- **state**: `waiting`, `done`, or `idle`

How to fill topic, completeness, and state:
- `MARKER:` has `($topic: X | $completeness: N | $state: S)` → use X, N, S directly
- `MARKER:` has `($topic: X)` only → use X for topic, reconstruct completeness/state from VISIBLE
- `[claude]` with no marker AND no conversation visible (startup UI, permission dialog, empty prompt) → topic = "üres session", completeness = "-", state = "idle"
- `[claude]` with no marker BUT has conversation visible → reconstruct topic/state from VISIBLE, completeness = "-"
- Non-claude panes → completeness = "-", state = "idle", topic from LASTCMD or dir basename

## Killing Windows

When the user wants to close a session (e.g., "végeztünk ezzel", "killelhetjük", "lődd ki"):

- Kill the tmux window with `tmux kill-window -t <session>:<window>`
- Do NOT send `/exit` to Claude Code
- NEVER kill the window/session where the current conversation is running. If unsure, ask.
