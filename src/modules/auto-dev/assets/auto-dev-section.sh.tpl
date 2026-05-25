#!/usr/bin/env bash
# auto-dev-section.sh — SwiftBar top-scope section for auto-dev managed repos
# Called by claude.10s.sh before the sessions section.
# Managed repos: GitHub repos with the "auto-dev" topic.
# Install submenu: repos without the topic (candidates).

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPTS_DIR="{{scripts_dir}}"
HOME_DIR="{{home}}"
JQ={{jq}}
TMUX_BIN={{tmux}}
STATE_DIR="$HOME_DIR/Documents/state/managed-iterations"
ACTIVITY_LOG="$STATE_DIR/activity.jsonl"

MANAGED_CACHE="/tmp/claude-toolkit-auto-dev-managed.json"
CANDIDATES_CACHE="/tmp/claude-toolkit-auto-dev-candidates.json"
CACHE_TTL=3600

# ── Cache helpers ─────────────────────────────────────────

_cache_age() {
    local f="$1"
    [[ ! -f "$f" ]] && { echo 99999; return; }
    local ts
    ts=$(grep -oE '"ts":[0-9]+' "$f" | grep -oE '[0-9]+')
    [[ -z "$ts" ]] && { echo 99999; return; }
    echo $(( $(date +%s) - ts ))
}

_refresh_repos() {
    local all ts managed candidates
    all=$(gh repo list --json nameWithOwner,repositoryTopics --limit 50 2>/dev/null)
    [[ -z "$all" ]] && return
    ts=$(date +%s)
    managed=$(echo "$all" | $JQ -r \
        '[.[] | select(.repositoryTopics | map(.name) | contains(["auto-dev"])) | .nameWithOwner]' \
        2>/dev/null)
    candidates=$(echo "$all" | $JQ -r \
        '[.[] | select(.repositoryTopics | map(.name) | contains(["auto-dev"]) | not) | .nameWithOwner]' \
        2>/dev/null)
    [[ -z "$managed" || -z "$candidates" ]] && return
    printf '{"repos":%s,"ts":%s}\n' "$managed" "$ts" > "$MANAGED_CACHE"
    printf '{"repos":%s,"ts":%s}\n' "$candidates" "$ts" > "$CANDIDATES_CACHE"
}

if (( $(_cache_age "$MANAGED_CACHE") > CACHE_TTL )); then
    ( _refresh_repos ) &>/dev/null &
fi

# ── Read data ─────────────────────────────────────────────

MANAGED_REPOS=""
[[ -f "$MANAGED_CACHE" ]] && MANAGED_REPOS=$($JQ -r '.repos[]?' "$MANAGED_CACHE" 2>/dev/null)

CANDIDATE_REPOS=""
[[ -f "$CANDIDATES_CACHE" ]] && CANDIDATE_REPOS=$($JQ -r '.repos[]?' "$CANDIDATES_CACHE" 2>/dev/null)

# ── Managed repos (top-scope) ─────────────────────────────

if [[ -n "$MANAGED_REPOS" ]]; then
    echo "---"

    while IFS= read -r REPO; do
        [[ -z "$REPO" ]] && continue

        REPO_SLUG="${REPO//\//-}"
        SESS="auto-dev-$REPO_SLUG"
        REPO_NAME="${REPO##*/}"

        # Runner status
        if $TMUX_BIN has-session -t "$SESS" 2>/dev/null; then
            RUNNER_STATUS="running"
            RUNNER_COLOR="#30d158"
        else
            RUNNER_STATUS="stopped"
            RUNNER_COLOR="#ff453a"
        fi

        # Last activity
        LAST_OUTCOME="" LAST_TODO=""
        if [[ -f "$ACTIVITY_LOG" ]]; then
            LAST_ENTRY=$(grep "\"${REPO}\"" "$ACTIVITY_LOG" 2>/dev/null | tail -1)
            if [[ -n "$LAST_ENTRY" ]]; then
                LAST_OUTCOME=$($JQ -r '.outcome // ""' 2>/dev/null <<< "$LAST_ENTRY")
                LAST_TODO=$($JQ -r '.todo // ""' 2>/dev/null <<< "$LAST_ENTRY" | cut -c1-30)
            fi
        fi

        case "$LAST_OUTCOME" in
            completed) LAST_ICON="✓" ;;
            blocked)   LAST_ICON="⊘" ;;
            question)  LAST_ICON="?" ;;
            crash)     LAST_ICON="✗" ;;
            *)         LAST_ICON=""  ;;
        esac

        TITLE="$REPO_NAME"
        [[ -n "$LAST_ICON" && -n "$LAST_TODO" ]] && TITLE="$TITLE  $LAST_ICON $LAST_TODO"
        echo "$TITLE | size=13"

        # Runner controls
        echo "--● Runner: $RUNNER_STATUS | color=$RUNNER_COLOR size=12"
        if [[ "$RUNNER_STATUS" == "stopped" ]]; then
            echo "--Start runner | bash=$SCRIPTS_DIR/auto-dev-runner-control.sh param1=start param2=$REPO terminal=false refresh=true size=12"
        else
            echo "--Open runner pane | bash=$TMUX_BIN param1=new-window param2=-t param3=$SESS terminal=false size=12"
            echo "--Stop runner | bash=$SCRIPTS_DIR/auto-dev-runner-control.sh param1=stop param2=$REPO terminal=false refresh=true size=12"
        fi

        echo "-----"

        # Recent cycles
        if [[ -f "$ACTIVITY_LOG" ]]; then
            ENTRIES=$(grep "\"${REPO}\"" "$ACTIVITY_LOG" 2>/dev/null | tail -5 | tac)
            if [[ -n "$ENTRIES" ]]; then
                echo "--Recent cycles | size=11 color=#888888"
                while IFS= read -r ENTRY; do
                    [[ -z "$ENTRY" ]] && continue
                    OUTCOME=$($JQ -r '.outcome // "?"' 2>/dev/null <<< "$ENTRY")
                    TODO=$($JQ -r '.todo // ""' 2>/dev/null <<< "$ENTRY" | cut -c1-35)
                    ENTRY_TS=$($JQ -r '.ts // 0' 2>/dev/null <<< "$ENTRY")
                    MODEL=$($JQ -r '.model // ""' 2>/dev/null <<< "$ENTRY" | sed 's/claude-//' | sed 's/-[0-9].*//')
                    PR_REF=$($JQ -r '.pr // ""' 2>/dev/null <<< "$ENTRY")

                    case "$OUTCOME" in
                        completed) ICON="✓"; COLOR="#30d158" ;;
                        blocked)   ICON="⊘"; COLOR="#ff9f0a" ;;
                        question)  ICON="?"; COLOR="#0a84ff" ;;
                        crash)     ICON="✗"; COLOR="#ff453a" ;;
                        *)         ICON="·"; COLOR="#888888" ;;
                    esac

                    AGE_MIN=$(( ($(date +%s) - ENTRY_TS) / 60 ))
                    if   (( AGE_MIN < 60 ));   then AGE="${AGE_MIN}m"
                    elif (( AGE_MIN < 1440 )); then AGE="$(( AGE_MIN / 60 ))h"
                    else                            AGE="$(( AGE_MIN / 1440 ))d"
                    fi

                    DISPLAY="$ICON $AGE ${TODO:-(no todo)}"
                    [[ -n "$MODEL" ]] && DISPLAY="$DISPLAY [$MODEL]"

                    if [[ -n "$PR_REF" ]]; then
                        PR_URL="https://github.com/$REPO/pull/${PR_REF##*#}"
                        echo "--$DISPLAY | color=$COLOR size=12 href=$PR_URL"
                    else
                        echo "--$DISPLAY | color=$COLOR size=12"
                    fi
                done <<< "$ENTRIES"
            else
                echo "--No cycles yet | size=12 color=#888888"
            fi
        fi

        echo "-----"
        echo "--Issues | href=https://github.com/$REPO/issues?q=label%3Aai size=12"
        echo "--Workflow runs | href=https://github.com/$REPO/actions/workflows/auto-dev.yml size=12"
        echo "--Repo | href=https://github.com/$REPO size=12"

    done <<< "$MANAGED_REPOS"
fi

# ── Install submenu ───────────────────────────────────────

[[ -z "$MANAGED_REPOS" ]] && echo "---"

if [[ -n "$CANDIDATE_REPOS" ]]; then
    echo "Install Auto-dev to repo… | size=12 color=#888888"
    while IFS= read -r REPO; do
        [[ -z "$REPO" ]] && continue
        REPO_NAME="${REPO##*/}"
        echo "--$REPO_NAME ($REPO) | bash=$SCRIPTS_DIR/auto-dev-runner-setup.sh param1=$REPO terminal=true refresh=true size=12"
    done <<< "$CANDIDATE_REPOS"
else
    # Cache not ready yet — osascript dialog will ask for repo name
    echo "Install Auto-dev to repo… | bash=$SCRIPTS_DIR/auto-dev-runner-setup.sh terminal=false refresh=true size=12 color=#888888"
fi
