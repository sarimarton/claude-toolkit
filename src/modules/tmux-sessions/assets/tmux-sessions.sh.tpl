#!/bin/bash
# AI session aggregator — scans tmux panes, summarizes via Claude.
# Raw output: ;-separated (machine-parseable). Display: aligned columns.
#
# Architecture: scan runs HERE (no LLM tool calls needed),
# output is piped to Claude for summarization only.

set -euo pipefail

SCAN_SCRIPT="{{scripts_dir}}/tmux-scan.sh"

usage() {
  cat <<'EOF'
ts — tmux AI session aggregator

Usage: ts [options]

Options:
  --raw       Output raw ;-separated format (for piping/scripting)
  --scan      Output raw scan data (before LLM summarization)
  --kill ID   Kill a tmux window (e.g. ts --kill vscode_-config:2)
  --help      Show this help

Examples:
  ts              Aligned column view of all sessions
  ts --raw        Raw ;-separated output for scripting
  ts --raw | grep claude   Filter claude sessions
  ts --kill vscode_-config:2
EOF
}

summarize() {
  local scan_output="$1"
  {{claude}} -p --no-session-persistence --model haiku <<EOF
You are a tmux session summarizer. Given scan data, output one line per pane.
No markdown, no bold, no headers, no introduction. Plain text only.

Fixed 6-field format for EVERY line:

pane_id; process; dir; topic; completeness; state

- pane_id: from PANE: line (e.g. vscode_-config:2)
- process: from [proc_type] tag (e.g. claude, zsh, node)
- dir: working directory from PANE: line
- topic: what this pane is about (5-10 words)
- completeness: task progress 0-100 (or "-" if not applicable)
- state: waiting, done, or idle

How to fill topic, completeness, and state:
- MARKER: has (\$topic: X | \$completeness: N | \$state: S) → use X, N, S directly
- MARKER: has (\$topic: X) only → use X for topic, reconstruct completeness/state from VISIBLE
- [claude] with no marker AND no conversation visible (startup UI, permission dialog, empty prompt) → topic = "üres session", completeness = "-", state = "idle"
- [claude] with no marker BUT has conversation visible → reconstruct topic/state from VISIBLE, completeness = "-"
- Non-claude panes → completeness = "-", state = "idle", topic from LASTCMD or dir basename

IMPORTANT: output ONLY the lines, nothing else. No introductory text, no summary, no explanation.

--- SCAN DATA ---
${scan_output}
EOF
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --kill)
    [ -z "${2:-}" ] && echo "Usage: ts --kill <session:window>" >&2 && exit 1
    {{tmux}} kill-window -t "$2"
    echo "Killed $2"
    exit 0
    ;;
  --scan)
    "$SCAN_SCRIPT"
    exit 0
    ;;
  --raw)
    scan_output=$("$SCAN_SCRIPT" 2>/dev/null)
    summarize "$scan_output" 2>/dev/null
    exit 0
    ;;
  "")
    scan_output=$("$SCAN_SCRIPT" 2>/dev/null)
    summarize "$scan_output" 2>/dev/null | column -t -s ';'
    ;;
  *)
    echo "Unknown option: $1 (try ts --help)" >&2
    exit 1
    ;;
esac
