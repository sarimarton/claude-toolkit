#!/usr/bin/env bash
# auto-dev-section.sh — SwiftBar top-scope section for auto-dev managed repos
# Called by claude.10s.sh before the sessions section.
# Managed repos: GitHub repos with the "auto-dev" topic.
# Install submenu: repos without the topic (candidates).

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPTS_DIR="{{scripts_dir}}"
HOME_DIR="{{home}}"
JQ={{jq}}
YQ={{yq}}
TMUX_BIN={{tmux}}
CONFIG_FILE="{{config_file}}"
STATE_DIR="$HOME_DIR/Documents/state/claude-toolkit/auto-dev"
ACTIVITY_LOG="$STATE_DIR/activity.jsonl"

# ── Auto-start runners once per boot ──────────────────────
# The menu renders right after SwiftBar launches at login, so this is the natural
# "menu startup" hook. A boot marker (kern.boottime vs marker mtime — same pattern
# as the swiftbar watchdog) makes it fire exactly once per boot, never on the
# recurring ~10s render. start-all itself is idempotent (skips running sessions).
AUTOSTART=$($YQ -r '.modules.autoDev.autostartRunners // true' "$CONFIG_FILE" 2>/dev/null)
if [[ "$AUTOSTART" == "true" ]]; then
    BOOT_MARKER="/tmp/.auto-dev-autostart-boot"
    boot_epoch=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*{ *sec *= *\([0-9]*\).*/\1/p')
    marker_mtime=0
    [[ -f "$BOOT_MARKER" ]] && marker_mtime=$(stat -f %m "$BOOT_MARKER" 2>/dev/null || echo 0)
    if [[ -n "$boot_epoch" ]] && (( marker_mtime < boot_epoch )); then
        : > "$BOOT_MARKER"   # mark before acting, so a crash can't loop us
        ( bash "$SCRIPTS_DIR/auto-dev-runner-control.sh" start-all ) &>/dev/null &
    fi
fi

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
        '[.[] | select((.repositoryTopics // []) | map(.name) | contains(["auto-dev"])) | .nameWithOwner] | sort' \
        2>/dev/null)
    candidates=$(echo "$all" | $JQ -r \
        '[.[] | select((.repositoryTopics // []) | map(.name) | contains(["auto-dev"]) | not) | .nameWithOwner] | sort' \
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

# Shared jq filter for menu labels: todo/summary/next fields are raw markdown
# (PR checklist lines, LLM output) flattened into a plain-text SwiftBar menu.
# Strip backticks (`) keeping their content, collapse whitespace, escape the
# pipe separator (→ │ ∣), then truncate with a trailing … (…) only if cut.
JQ_MENULABEL='def menulabel($n): (. // "") | gsub("`"; "") | gsub("\\s+"; " ") | gsub("[|]"; "∣") | (if (. | length) > $n then .[0:($n-1)] + "…" else . end);'

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

        # Last activity — parse multi-line JSONL with jq -s (one pass, all entries)
        LAST_OUTCOME="" LAST_TODO="" REPO_ENTRIES_JSON="[]"
        if [[ -f "$ACTIVITY_LOG" ]]; then
            REPO_ENTRIES_JSON=$($JQ -sc --arg r "$REPO" \
                '[.[] | select(.repo == $r)]' "$ACTIVITY_LOG" 2>/dev/null)
            IFS=$'\x1f' read -r LAST_OUTCOME LAST_TODO < <(
                $JQ -r "$JQ_MENULABEL"'last // {} | [(.outcome // ""), (.todo | menulabel(30))] | join("")' \
                    2>/dev/null <<< "$REPO_ENTRIES_JSON"
            )
        fi

        case "$LAST_OUTCOME" in
            completed) LAST_ICON="✓" ;;
            blocked)   LAST_ICON="⊘" ;;
            question)  LAST_ICON="?" ;;
            crash)     LAST_ICON="✗" ;;
            *)         LAST_ICON=""  ;;
        esac

        # Issue status from workflow-written summary
        ISSUE_SUMMARY=""
        CURRENT_AUTONOMY=""
        STATUS_JSON="$STATE_DIR/${REPO_SLUG}-status.json"
        if [[ -f "$STATUS_JSON" ]]; then
            IFS=$'\t' read -r TOTAL NEW READY IN_PROG BLOCKED CURRENT_AUTONOMY < <(
                $JQ -r '[
                    (.issues.total // 0 | tostring),
                    (.issues.new // 0 | tostring),
                    (.issues.ready // 0 | tostring),
                    (.issues.in_progress // 0 | tostring),
                    (.issues.blocked // 0 | tostring),
                    (.autonomy // "")
                ] | join("\t")' "$STATUS_JSON" 2>/dev/null
            )
            PARTS=""
            (( NEW > 0 ))     && PARTS="${PARTS}${NEW} new · "
            (( READY > 0 ))   && PARTS="${PARTS}${READY} ready · "
            (( IN_PROG > 0 )) && PARTS="${PARTS}${IN_PROG} in-progress · "
            (( BLOCKED > 0 )) && PARTS="${PARTS}${BLOCKED} blocked · "
            PARTS="${PARTS% · }"
            [[ -n "$PARTS" ]] && ISSUE_SUMMARY="${TOTAL} issues: ${PARTS}" || ISSUE_SUMMARY="${TOTAL} issues"
        fi

        TITLE="● $REPO_NAME"
        [[ -n "$LAST_ICON" && -n "$LAST_TODO" ]] && TITLE="$TITLE  $LAST_ICON $LAST_TODO"
        echo "$TITLE | size=13 color=$RUNNER_COLOR"

        if [[ -n "$ISSUE_SUMMARY" ]]; then
            echo "--$ISSUE_SUMMARY | size=12 color=#888888 href=https://github.com/$REPO/issues?q=label%3Aai"
            echo "-----"
        fi

        # Runner controls
        echo "--● Runner: $RUNNER_STATUS | color=$RUNNER_COLOR size=12"
        if [[ "$RUNNER_STATUS" == "stopped" ]]; then
            echo "--Start runner | bash=$SCRIPTS_DIR/auto-dev-runner-control.sh param1=start param2=$REPO terminal=false refresh=true size=12"
        else
            echo "--Open runner pane | bash=$SCRIPTS_DIR/auto-dev-attach.sh param1=$SESS terminal=false size=12"
            echo "--Stop runner | bash=$SCRIPTS_DIR/auto-dev-runner-control.sh param1=stop param2=$REPO terminal=false refresh=true size=12"
        fi

        echo "-----"

        # Activity section — REPO_ENTRIES_JSON already loaded above (no extra jq -s)
        _has_entries=$($JQ -r 'if length > 0 then "yes" else "no" end' 2>/dev/null <<< "$REPO_ENTRIES_JSON")
        if [[ "$_has_entries" == "yes" ]]; then
            NOW_S=$(date +%s)

            # Last PM report — always pinned, regardless of how many cycles followed
            IFS=$'\x1f' read -r PM_TS PM_SUM PM_CNT PM_NEXT < <($JQ -r "$JQ_MENULABEL"'
                [.[] | select(.agent == "pm")] |
                if length > 0 then last |
                [
                    ((.ts // 0) | tostring),
                    (.summary | menulabel(60)),
                    ((.actions // 0) | tostring),
                    (.next | menulabel(80))
                ] | join("\u001f")
                else empty end
            ' 2>/dev/null <<< "$REPO_ENTRIES_JSON")
            if [[ -n "$PM_TS" ]]; then
                PM_AGE_MIN=$(( (NOW_S - PM_TS) / 60 ))
                if   (( PM_AGE_MIN < 60 ));   then PM_AGE="${PM_AGE_MIN}m"
                elif (( PM_AGE_MIN < 1440 )); then PM_AGE="$(( PM_AGE_MIN / 60 ))h"
                else                               PM_AGE="$(( PM_AGE_MIN / 1440 ))d"
                fi
                PM_DISPLAY="📋 $PM_AGE PM: ${PM_SUM:-(no summary)} (${PM_CNT})"
                PM_TT=""
                [[ -n "$PM_NEXT" ]] && PM_TT=" tooltip=$PM_NEXT"
                echo "--$PM_DISPLAY | color=#bf5af2 size=12 href=https://github.com/$REPO/actions/workflows/auto-dev-pm.yml${PM_TT}"
            fi

            echo "-----"

            # Last 5 dev cycles (non-PM)
            _has_cycles=$($JQ -r '[.[] | select((.agent // "auto-dev") != "pm")] | if length > 0 then "yes" else "no" end' 2>/dev/null <<< "$REPO_ENTRIES_JSON")
            if [[ "$_has_cycles" == "yes" ]]; then
                echo "--Cycles | size=11 color=#888888"
                while IFS=$'\x1f' read -r ENTRY_TS OUTCOME TODO PR_REF; do
                    AGE_MIN=$(( (NOW_S - ENTRY_TS) / 60 ))
                    if   (( AGE_MIN < 60 ));   then AGE="${AGE_MIN}m"
                    elif (( AGE_MIN < 1440 )); then AGE="$(( AGE_MIN / 60 ))h"
                    else                            AGE="$(( AGE_MIN / 1440 ))d"
                    fi

                    case "$OUTCOME" in
                        completed) ICON="✓"; COLOR="#30d158" ;;
                        blocked)   ICON="⊘"; COLOR="#ff9f0a" ;;
                        question)  ICON="?"; COLOR="#0a84ff" ;;
                        crash)     ICON="✗"; COLOR="#ff453a" ;;
                        *)         ICON="·"; COLOR="#888888" ;;
                    esac

                    DISPLAY="$ICON $AGE ${TODO:-(no todo)}"

                    if [[ -n "$PR_REF" ]]; then
                        PR_URL="https://github.com/$REPO/pull/${PR_REF##*#}"
                        echo "--$DISPLAY | color=$COLOR size=12 href=$PR_URL"
                    else
                        echo "--$DISPLAY | color=$COLOR size=12"
                    fi
                done < <($JQ -r "$JQ_MENULABEL"'
                    [.[] | select((.agent // "auto-dev") != "pm")] | .[-5:] | reverse[] |
                    [
                        ((.ts // 0) | tostring),
                        (.outcome // "?"),
                        (.todo | menulabel(40)),
                        (.pr // "")
                    ] | join("\u001f")
                ' 2>/dev/null <<< "$REPO_ENTRIES_JSON")
            fi
        else
            echo "--No cycles yet | size=12 color=#888888"
        fi

        echo "-----"
        echo "--Issues | href=https://github.com/$REPO/issues?q=label%3Aai size=12"
        echo "--Workflow runs | href=https://github.com/$REPO/actions/workflows/auto-dev-cycle.yml size=12"
        echo "--Repo | href=https://github.com/$REPO size=12"
        echo "-----"
        if [[ -n "$CURRENT_AUTONOMY" ]]; then
            echo "--Autonomy: $CURRENT_AUTONOMY | bash=$SCRIPTS_DIR/auto-dev-config.sh param1=$REPO terminal=false refresh=false size=12"
        else
            echo "--Config… | bash=$SCRIPTS_DIR/auto-dev-config.sh param1=$REPO terminal=false refresh=false size=12"
        fi
        echo "--Update Auto-dev workflow files… | bash=$SCRIPTS_DIR/auto-dev-reinstall.sh param1=$REPO terminal=false refresh=false size=12"
        echo "--Re-register Runner… | bash=$SCRIPTS_DIR/auto-dev-reregister.sh param1=$REPO terminal=false refresh=false size=12"
        echo "--Run PM agent… | bash=$SCRIPTS_DIR/auto-dev-pm-run.sh param1=$REPO terminal=false refresh=true size=12"

    done <<< "$MANAGED_REPOS"
fi

[[ -z "$MANAGED_REPOS" ]] && echo "---"
