#!/usr/bin/env bash
# auto-dev-section.sh — SwiftBar section for auto-dev module
# Called by the main claude.10s.sh plugin via extension point.
# Outputs SwiftBar menu items for each configured repo.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPTS_DIR="{{scripts_dir}}"
HOME_DIR="{{home}}"
CONFIG_FILE="{{config_file}}"
YQ={{yq}}
TMUX_BIN={{tmux}}
STATE_DIR="$HOME_DIR/Documents/state/managed-iterations"
ACTIVITY_LOG="$STATE_DIR/activity.jsonl"
RUNNERS_DIR="$HOME_DIR/.config/claude-toolkit/runners"

# ── Read configured repos from config.yaml ────────────
REPOS=""
if [[ -f "$CONFIG_FILE" ]]; then
  REPOS=$($YQ -r '.autoDev.repos[]? | .github' "$CONFIG_FILE" 2>/dev/null || true)
fi

[[ -z "$REPOS" ]] && exit 0

# ── Ansi helpers (match main plugin style) ────────────
A_DIM=$'\e[2m'; A_RST=$'\e[0m'; A_BOLD=$'\e[1m'

# ── Section separator + header ────────────────────────
echo "---"
echo "Auto-dev | size=11 color=#888888"

# ── Per-repo submenu ──────────────────────────────────
while IFS= read -r REPO; do
  [[ -z "$REPO" ]] && continue

  REPO_SLUG="${REPO//\//-}"
  SESS="auto-dev-$REPO_SLUG"
  REPO_NAME="${REPO##*/}"

  # Runner status
  if $TMUX_BIN has-session -t "$SESS" 2>/dev/null; then
    RUNNER_STATUS="●"
    RUNNER_COLOR="#30d158"  # green
    RUNNER_STATUS_TEXT="running"
  else
    RUNNER_STATUS="●"
    RUNNER_COLOR="#ff453a"  # red
    RUNNER_STATUS_TEXT="stopped"
  fi

  # Last activity for this repo
  LAST_OUTCOME=""
  if [[ -f "$ACTIVITY_LOG" ]]; then
    LAST_ENTRY=$(grep "\"${REPO}\"" "$ACTIVITY_LOG" 2>/dev/null | tail -1)
    if [[ -n "$LAST_ENTRY" ]]; then
      LAST_OUTCOME=$(echo "$LAST_ENTRY" | jq -r '.outcome // ""' 2>/dev/null)
      LAST_TODO=$(echo "$LAST_ENTRY" | jq -r '.todo // ""' 2>/dev/null | cut -c1-40)
      LAST_TS=$(echo "$LAST_ENTRY" | jq -r '.ts // 0' 2>/dev/null)
      NOW=$(date +%s)
      AGE_MIN=$(( (NOW - LAST_TS) / 60 ))
      if (( AGE_MIN < 60 )); then
        AGE_STR="${AGE_MIN}m ago"
      elif (( AGE_MIN < 1440 )); then
        AGE_STR="$(( AGE_MIN / 60 ))h ago"
      else
        AGE_STR="$(( AGE_MIN / 1440 ))d ago"
      fi
    fi
  fi

  # Submenu header line
  echo "${REPO_NAME} | size=13"

  # Runner status + controls
  echo "--${RUNNER_STATUS} Runner: ${RUNNER_STATUS_TEXT} | color=${RUNNER_COLOR} size=12"

  if [[ "$RUNNER_STATUS_TEXT" == "stopped" ]]; then
    echo "--Start runner | bash=$SCRIPTS_DIR/auto-dev-runner-control.sh param1=start param2=$REPO terminal=false refresh=true size=12"
  else
    echo "--Open runner pane | bash=$TMUX_BIN param1=new-window param2=-t param3=$SESS terminal=false refresh=false size=12"
    echo "--Stop runner | bash=$SCRIPTS_DIR/auto-dev-runner-control.sh param1=stop param2=$REPO terminal=false refresh=true size=12"
  fi

  echo "-----"

  # Last 5 activity log entries for this repo
  if [[ -f "$ACTIVITY_LOG" ]]; then
    ENTRIES=$(grep "\"${REPO}\"" "$ACTIVITY_LOG" 2>/dev/null | tail -5 | tac)
    if [[ -n "$ENTRIES" ]]; then
      echo "--Recent cycles | size=11 color=#888888"
      while IFS= read -r ENTRY; do
        [[ -z "$ENTRY" ]] && continue
        OUTCOME=$(echo "$ENTRY" | jq -r '.outcome // "?"' 2>/dev/null)
        TODO=$(echo "$ENTRY" | jq -r '.todo // ""' 2>/dev/null | cut -c1-35)
        ENTRY_TS=$(echo "$ENTRY" | jq -r '.ts // 0' 2>/dev/null)
        MODEL=$(echo "$ENTRY" | jq -r '.model // ""' 2>/dev/null | sed 's/claude-//' | sed 's/-[0-9].*//')
        PR_REF=$(echo "$ENTRY" | jq -r '.pr // ""' 2>/dev/null)

        case "$OUTCOME" in
          completed) ICON="✓"; COLOR="#30d158" ;;
          blocked)   ICON="⊘"; COLOR="#ff9f0a" ;;
          question)  ICON="?"; COLOR="#0a84ff" ;;
          crash)     ICON="✗"; COLOR="#ff453a" ;;
          *)         ICON="·"; COLOR="#888888" ;;
        esac

        ENTRY_AGE_MIN=$(( ($(date +%s) - ENTRY_TS) / 60 ))
        if (( ENTRY_AGE_MIN < 60 )); then
          ENTRY_AGE="${ENTRY_AGE_MIN}m"
        elif (( ENTRY_AGE_MIN < 1440 )); then
          ENTRY_AGE="$(( ENTRY_AGE_MIN / 60 ))h"
        else
          ENTRY_AGE="$(( ENTRY_AGE_MIN / 1440 ))d"
        fi

        DISPLAY="${ICON} ${ENTRY_AGE} ${TODO:-(no todo)}"
        [[ -n "$MODEL" ]] && DISPLAY="$DISPLAY [$MODEL]"

        if [[ -n "$PR_REF" ]]; then
          PR_NUM="${PR_REF##*#}"
          PR_URL="https://github.com/$REPO/pull/$PR_NUM"
          echo "--${DISPLAY} | color=${COLOR} size=12 href=$PR_URL"
        else
          echo "--${DISPLAY} | color=${COLOR} size=12"
        fi
      done <<< "$ENTRIES"
    else
      echo "--No cycles yet | size=12 color=#888888"
    fi
  else
    echo "--No activity log yet | size=12 color=#888888"
  fi

  echo "-----"

  # Config and repo links
  REPO_URL="https://github.com/$REPO"
  ISSUES_URL="https://github.com/$REPO/issues?q=label%3Aai"
  ACTIONS_URL="https://github.com/$REPO/actions/workflows/auto-dev.yml"

  echo "--Open issues | href=$ISSUES_URL size=12"
  echo "--Workflow runs | href=$ACTIONS_URL size=12"
  echo "--Repo on GitHub | href=$REPO_URL size=12"

done <<< "$REPOS"

# ── Install to new repo ───────────────────────────────
echo "Install auto-dev in another repo… | bash=$SCRIPTS_DIR/auto-dev-runner-setup.sh terminal=true size=12 color=#888888"
