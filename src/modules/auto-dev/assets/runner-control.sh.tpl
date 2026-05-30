#!/usr/bin/env bash
# auto-dev-runner-control.sh — Start, stop, or query status of a self-hosted runner
#
# Usage:
#   auto-dev-runner-control.sh start     <owner/repo>
#   auto-dev-runner-control.sh stop      <owner/repo>
#   auto-dev-runner-control.sh status    <owner/repo>
#   auto-dev-runner-control.sh list
#   auto-dev-runner-control.sh start-all  (start every set-up runner that is stopped)

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

TMUX_BIN={{tmux}}
HOME_DIR="{{home}}"
RUNNERS_DIR="$HOME_DIR/.config/claude-toolkit/runners"

ACTION="${1:-list}"
REPO="${2:-}"

# ── Helper: tmux session name for a repo ──────────────
session_name() {
  local repo="$1"
  echo "auto-dev-${repo//\//-}"
}

# ── Helper: runner dir for a repo ─────────────────────
runner_dir() {
  local repo="$1"
  echo "$RUNNERS_DIR/${repo//\//-}"
}

# ── Helper: check if runner is running ────────────────
is_running() {
  local sess
  sess=$(session_name "$1")
  $TMUX_BIN has-session -t "$sess" 2>/dev/null && return 0 || return 1
}

# ── list ───────────────────────────────────────────────
if [[ "$ACTION" == "list" ]]; then
  if [[ ! -d "$RUNNERS_DIR" ]]; then
    echo "No runners configured."
    exit 0
  fi
  for dir in "$RUNNERS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    if [[ -f "${dir}.repo-name" ]]; then
      repo=$(cat "${dir}.repo-name")
    else
      slug="${dir%/}"; slug="${slug##*/}"
      repo="${slug/-//}"
    fi
    sess=$(session_name "$repo")
    if $TMUX_BIN has-session -t "$sess" 2>/dev/null; then
      echo "$repo  running  (session: $sess)"
    else
      echo "$repo  stopped"
    fi
  done
  exit 0
fi

# ── start-all ──────────────────────────────────────────
# Start every locally set-up runner that is currently stopped. Iterates the
# runner dirs (the local source of truth), not any network-fetched repo list, so
# it works at boot before the menu's GitHub topic cache is populated.
if [[ "$ACTION" == "start-all" ]]; then
  [[ -d "$RUNNERS_DIR" ]] || { echo "No runners configured."; exit 0; }
  for dir in "$RUNNERS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    [[ -f "${dir}run.sh" ]] || continue
    if [[ -f "${dir}.repo-name" ]]; then
      repo=$(cat "${dir}.repo-name")
    else
      slug="${dir%/}"; slug="${slug##*/}"
      repo="${slug/-//}"
    fi
    sess=$(session_name "$repo")
    if $TMUX_BIN has-session -t "$sess" 2>/dev/null; then
      echo "$repo already running"
    else
      $TMUX_BIN new-session -d -s "$sess" -c "${dir%/}" './run.sh'
      echo "Runner started for $repo (session: $sess)"
    fi
  done
  exit 0
fi

if [[ -z "$REPO" ]]; then
  echo "Usage: auto-dev-runner-control.sh <start|stop|status> <owner/repo>"
  exit 1
fi

SESS=$(session_name "$REPO")
RDIR=$(runner_dir "$REPO")

# ── start ──────────────────────────────────────────────
if [[ "$ACTION" == "start" ]]; then
  if [[ ! -f "$RDIR/run.sh" ]]; then
    echo "Error: runner not set up for $REPO. Run auto-dev-runner-setup.sh first."
    exit 1
  fi
  if is_running "$REPO"; then
    echo "Runner for $REPO is already running (session: $SESS)"
    exit 0
  fi
  $TMUX_BIN new-session -d -s "$SESS" -c "$RDIR" './run.sh'
  echo "Runner started for $REPO (session: $SESS)"
  exit 0
fi

# ── stop ───────────────────────────────────────────────
if [[ "$ACTION" == "stop" ]]; then
  if ! is_running "$REPO"; then
    echo "Runner for $REPO is not running."
    exit 0
  fi
  $TMUX_BIN kill-session -t "$SESS"
  echo "Runner stopped for $REPO"
  exit 0
fi

# ── status ─────────────────────────────────────────────
if [[ "$ACTION" == "status" ]]; then
  if is_running "$REPO"; then
    echo "running"
  else
    echo "stopped"
  fi
  exit 0
fi

echo "Unknown action: $ACTION"
exit 1
