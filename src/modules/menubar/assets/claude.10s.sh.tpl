#!/usr/bin/env bash
# claude.10s.sh — Claude Code usage & sessions menu bar plugin for SwiftBar
# Replaces hammerspoon/claude-usage.lua + claude-sessions.lua
#
# Features:
#   - Menu bar: ✻ 77% (1h 46m) with color coding
#   - Dropdown: usage details, active sessions with topic/completeness
#   - Click session → focus (attached) or attach (detached)
#   - Option+click session → kill
#   - Refresh / stop monitor controls

# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

POLL_SCRIPT="{{scripts_dir}}/claude-usage-poll.sh"
TMUX_BIN={{tmux}}
HELPERS="{{scripts_dir}}"
SHOW_REMAINING=true
HOME_DIR="{{home}}"
CONFIG_FILE="{{config_file}}"

# ── Multi-account: determine primary account ────────────
MULTI_ACCOUNT=false
PRIMARY_ACCOUNT=""
ALL_ACCOUNTS=""
if [ -f "$CONFIG_FILE" ]; then
  account_info=$(python3 -c "
try:
    import yaml
    with open('$CONFIG_FILE') as f:
        cfg = yaml.safe_load(f) or {}
    accounts = cfg.get('accounts', [])
    if not accounts:
        print()
    else:
        primary = ''
        names = []
        for a in accounts:
            n = a.get('name', '')
            if n:
                names.append(n)
                if a.get('primary') or not primary:
                    primary = n
        print(primary)
        for n in names:
            print(n)
except:
    print()
" 2>/dev/null)
  if [ -n "$account_info" ]; then
    PRIMARY_ACCOUNT=$(echo "$account_info" | head -1)
    ALL_ACCOUNTS=$(echo "$account_info" | tail -n +2)
    acct_count=$(echo "$ALL_ACCOUNTS" | wc -l | tr -d ' ')
    (( acct_count > 1 )) && MULTI_ACCOUNT=true
  fi
fi

# Derive file paths from primary account
if [ -n "$PRIMARY_ACCOUNT" ]; then
  USAGE_FILE="/tmp/claude-usage-${PRIMARY_ACCOUNT}.json"
else
  USAGE_FILE="/tmp/claude-usage.json"
fi

# ── JSON helpers (pure bash — no python3 overhead) ───────

json_str()  { grep -oE "\"$1\":[[:space:]]*\"[^\"]*\"" "$USAGE_FILE" 2>/dev/null | head -1 | sed "s/\"$1\":[[:space:]]*\"//;s/\"$//" ; }
json_num()  { grep -oE "\"$1\":[[:space:]]*[0-9]+" "$USAGE_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*$' ; }

# ── Auto-poll: trigger refresh if data is stale (>3 min) ──
POLL_INTERVAL=180  # 3 minutes
POLL_LOCK="/tmp/claude-usage-poll.lock"

if [[ -f "$USAGE_FILE" ]]; then
    file_ts=$(json_num ts)
    now=$(date +%s)
    age=$(( now - ${file_ts:-0} ))
else
    age=$((POLL_INTERVAL + 1))
fi

if (( age > POLL_INTERVAL )); then
    # Only start poll if not already running
    if [[ ! -f "$POLL_LOCK" ]] || ! kill -0 "$(cat "$POLL_LOCK" 2>/dev/null)" 2>/dev/null; then
        ( echo $$ > "$POLL_LOCK"; bash "$POLL_SCRIPT"; rm -f "$POLL_LOCK" ) &>/dev/null &
    fi
fi

# ── Read usage data ──────────────────────────────────────

pct=$(json_num pct)
reset_ts=$(json_num reset_ts)
weekly_pct=$(json_num weekly_pct)
weekly_reset_ts=$(json_num weekly_reset_ts)
error=$(json_str error)
error_detail=$(json_str error_detail)
phase=$(json_str phase)
ts=$(json_num ts)

# Determine if weekly limit is the binding constraint
weekly_capped=false
[[ -n "$weekly_pct" ]] && (( weekly_pct >= 100 )) && weekly_capped=true

# Compute mins_left dynamically
# Default: show session (5h) reset. Show weekly only when weekly is the binding cap.
now=$(date +%s)
mins_left=""
effective_reset_ts=""
if $weekly_capped; then
    [[ -n "$weekly_reset_ts" ]] && effective_reset_ts="$weekly_reset_ts"
elif [[ -n "$reset_ts" && -n "$pct" ]] && (( pct > 0 )); then
    effective_reset_ts="$reset_ts"
fi
if [[ -n "$effective_reset_ts" ]]; then
    mins_left=$(( (effective_reset_ts - now) / 60 ))
    (( mins_left < 0 )) && mins_left=0
fi

# ── Color helpers ────────────────────────────────────────
# SwiftBar ansi=true supports basic 16-color ANSI only (not 24-bit true color)

A_RST=$'\033[0m'
A_LOGO=$'\033[38;5;214m'   # orange
A_DIM=$'\033[38;5;243m'    # gray
A_YELLOW=$'\033[33m'       # yellow
A_MAGENTA=$'\033[38;5;211m' # muted pink
A_GREEN=$'\033[38;5;34m'   # green
A_RED=$'\033[31m'
A_BRED=$'\033[91m'         # bright red

pct_color() {
    local p=$1
    if $SHOW_REMAINING; then
        (( p > 50 )) && { echo "#33CC33"; return; }
        (( p > 25 )) && { echo "#E6B310"; return; }
        (( p > 10 )) && { echo "#E65A26"; return; }
        echo "#F22626"
    else
        (( p < 50 )) && { echo "#33CC33"; return; }
        (( p < 75 )) && { echo "#E6B310"; return; }
        (( p < 90 )) && { echo "#E65A26"; return; }
        echo "#F22626"
    fi
}

pct_ansi() {
    local p=$1
    if $SHOW_REMAINING; then
        (( p > 50 )) && { echo "$A_GREEN"; return; }
        (( p > 25 )) && { echo "$A_YELLOW"; return; }
        (( p > 10 )) && { echo "$A_BRED"; return; }
        echo "$A_RED"
    else
        (( p < 50 )) && { echo "$A_GREEN"; return; }
        (( p < 75 )) && { echo "$A_YELLOW"; return; }
        (( p < 90 )) && { echo "$A_BRED"; return; }
        echo "$A_RED"
    fi
}

comp_ansi() {
    local c=$1
    (( c >= 100 )) && { echo "$A_GREEN"; return; }
    (( c >= 50 ))  && { echo "$A_YELLOW"; return; }
    echo "$A_RED"
}

comp_color() {
    local c=$1
    (( c >= 100 )) && { echo "#33B833"; return; }
    (( c >= 50 ))  && { echo "#E6B310"; return; }
    echo "#E64D33"
}

format_time() {
    local m=${1:-0}
    echo "$((m / 60))h $((m % 60))m"
}

format_ago() {
    local ts=$1
    [[ -z "$ts" ]] && return
    local mins=$(( ($(date +%s) - ts) / 60 ))
    if   (( mins < 1 ));  then echo "updated just now"
    elif (( mins == 1 )); then echo "updated 1 min ago"
    else echo "updated ${mins} min ago"
    fi
}

# ── Menu bar title ───────────────────────────────────────

if [[ -n "$pct" ]]; then
    if $weekly_capped; then
        display_pct=0
    elif $SHOW_REMAINING; then
        display_pct=$((100 - pct))
    else
        display_pct=$pct
    fi
    if [[ "$error" == "usage_unavailable" ]]; then
        pct_a="$A_DIM"  # stale data → gray
    else
        pct_a=$(pct_ansi $display_pct)
    fi
    title="${A_LOGO}✻ ${pct_a}${display_pct}%"
    $weekly_capped && title="$title${A_YELLOW}W"
    [[ -n "$mins_left" ]] && title="$title ${A_DIM}($(format_time $mins_left))"
    $MULTI_ACCOUNT && title="$title ${A_DIM}$PRIMARY_ACCOUNT"
    echo "${title}${A_RST} | ansi=true size=12"
elif [[ "$error" == "usage_unavailable" ]]; then
    echo "${A_LOGO}✻ ${A_YELLOW}⚠${A_RST} | ansi=true size=12"
elif [[ -n "$phase" && -z "$error" ]]; then
    label="$phase"
    case "$phase" in
        session) label="Checking session" ;; claude) label="Checking Claude" ;;
        start)   label="Starting Claude"  ;; restart) label="Restarting" ;;
        send)    label="Sending /usage"   ;; wait) label="Waiting" ;;
        parse)   label="Parsing" ;;
    esac
    echo "${A_LOGO}✻ ${A_DIM}${label}…${A_RST} | ansi=true size=12"
else
    echo "${A_LOGO}✻ ${A_DIM}--${A_RST} | ansi=true size=12"
fi

echo "---"

# ── Usage details ────────────────────────────────────────

if [[ -n "$pct" ]]; then
    remaining_label=$($SHOW_REMAINING && echo "remaining" || echo "used")
    # When weekly is capped, show actual session % on the status line too
    if $weekly_capped; then
        if $SHOW_REMAINING; then session_display=$((100 - pct)); else session_display=$pct; fi
        status_line="⊘ Weekly limit reached · session ${session_display}% ${remaining_label}"
    else
        status_line="${display_pct}% ${remaining_label}"
    fi
    [[ -n "$mins_left" ]] && status_line="$status_line · resets in $(format_time $mins_left)"
    ago=$(format_ago "$ts")
    [[ -n "$ago" ]] && status_line="$status_line ($ago)"
    if [[ "$error" == "usage_unavailable" ]]; then
        stale_reason="stale"
        [[ -n "$error_detail" ]] && stale_reason="stale: $error_detail"
        status_line="$status_line · ⚠ $stale_reason"
    elif [[ -n "$phase" ]]; then
        status_line="$status_line · refreshing…"
    fi
    echo "${A_DIM}${status_line}${A_RST} | ansi=true size=13"
    # Weekly usage line (show when data available and not already shown in main line)
    if [[ -n "$weekly_pct" ]] && ! $weekly_capped; then
        if $SHOW_REMAINING; then weekly_display=$((100 - weekly_pct)); else weekly_display=$weekly_pct; fi
        weekly_line="Week: ${weekly_display}% ${remaining_label}"
        if [[ -n "$weekly_reset_ts" ]]; then
            weekly_mins=$(( (weekly_reset_ts - now) / 60 ))
            (( weekly_mins > 0 )) && weekly_line="$weekly_line · resets in $(format_time $weekly_mins)"
        fi
        echo "${A_DIM}${weekly_line}${A_RST} | ansi=true size=13"
    fi
elif [[ "$error" == "usage_unavailable" ]]; then
    ago=$(format_ago "$ts")
    line="Usage API unavailable"
    [[ -n "$ago" ]] && line="$line ($ago)"
    echo "$line"
elif [[ "$error" == "oauth_scope_error" ]]; then
    echo "OAuth token blocks /usage | color=#888888 sfimage=exclamationmark.triangle"
elif [[ -n "$error" && "$error" != "" ]]; then
    echo "$error | color=#888888"
else
    echo "No data yet | color=#888888"
fi

# ── Sessions ─────────────────────────────────────────────

echo "---"

# Scan tmux for Claude Code sessions
seen_windows=""
has_sessions=false

# Global peek lock — max 1 concurrent peek generation across all sessions
PEEK_GLOBAL_LOCK="/tmp/claude-peek-global.lock"
peek_slot_available=true
if [[ -f "$PEEK_GLOBAL_LOCK" ]] && kill -0 "$(cat "$PEEK_GLOBAL_LOCK" 2>/dev/null)" 2>/dev/null; then
    peek_slot_available=false
fi

while IFS=$'\t' read -r sess_name attached win_name proc path pane_title pane_id window_id; do
    # Filter: only Claude processes (version pattern like 1.2.3), exclude monitor
    [[ ! "$proc" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
    [[ "$sess_name" == "claude_usage_mon" ]] && continue

    # Dedup by window_id (bash 3.2 compatible)
    case "$seen_windows" in *"|$window_id|"*) continue ;; esac
    seen_windows="${seen_windows}|${window_id}|"
    has_sessions=true

    # Shorten path
    short_path="${path/#$HOME_DIR/\~}"

    # Capture pane buffer once, reuse for topic + peek
    pane_buf=$(TMUX= $TMUX_BIN capture-pane -t "$pane_id" -p -S -300 2>/dev/null)

    # Extract $topic: and $completeness:
    topic_line=$(echo "$pane_buf" | grep '\$topic:' | tail -1)
    topic_text=""
    comp_text=""
    if [[ -n "$topic_line" ]]; then
        topic_text=$(echo "$topic_line" | sed -n 's/.*\$topic:[[:space:]]*\([^|]*\).*/\1/p' | sed 's/[[:space:]]*$//')
        comp_text=$(echo "$topic_line" | sed -n 's/.*\$completeness:[[:space:]]*\([0-9]*\).*/\1/p')
    fi

    # Peek: AI-generated summary cached in /tmp, regenerated when buffer changes
    nbsp=$'\xc2\xa0'
    peek_cache="/tmp/claude-peek-${sess_name}.txt"
    peek_hash_file="/tmp/claude-peek-${sess_name}.hash"
    peek_lock="/tmp/claude-peek-${sess_name}.lock"
    buf_tail=$(echo "$pane_buf" | sed '/^[[:space:]]*$/d' | tail -50)
    buf_hash=$(echo "$buf_tail" | md5 -q 2>/dev/null || echo "$buf_tail" | md5sum 2>/dev/null | cut -d' ' -f1)
    old_hash=""
    [[ -f "$peek_hash_file" ]] && old_hash=$(cat "$peek_hash_file")

    regen=true
    # Dedup: skip if a generation is already running for this session
    if [[ -f "$peek_lock" ]] && kill -0 "$(cat "$peek_lock" 2>/dev/null)" 2>/dev/null; then
        regen=false
    fi
    # Global dedup: skip if any peek generation is running
    if $regen && ! $peek_slot_available; then
        regen=false
    fi
    # Cooldown: skip if last generation was less than 2 minutes ago
    if $regen && [[ -f "$peek_hash_file" ]]; then
        last_gen=$(stat -f %m "$peek_hash_file" 2>/dev/null || echo 0)
        (( $(date +%s) - last_gen < 120 )) && regen=false
    fi
    # State-aware: skip during active streaming (only generate for waiting/done)
    state_text=$(echo "$topic_line" | sed -n 's/.*\$state:[[:space:]]*\([a-z]*\).*/\1/p')
    if [[ -n "$state_text" && "$state_text" != "waiting" && "$state_text" != "done" ]]; then
        regen=false
    fi

    if [[ "$buf_hash" != "$old_hash" && -n "$buf_tail" && "$regen" == true && "$peek_slot_available" == true ]]; then
        peek_slot_available=false
        # Generate summary in background, detached from SwiftBar stdout pipe
        # Timeout: 30s max to prevent process accumulation
        (
            _cleanup() { rm -f "$peek_lock" "$PEEK_GLOBAL_LOCK"; }
            trap _cleanup EXIT
            summary=$(echo "$buf_tail" | CLAUDECODE= perl -e 'alarm 30; exec @ARGV' {{claude}} -p --no-session-persistence --model haiku "Foglald össze ezt a Claude Code session terminal outputját 1-2 mondatban. A user-re E/2-ben utalj ('kérted', 'akartad'), a Claude-ra E/1-ben ('szerkesztettem', 'dolgozom rajta'). Plain text, ne használj markdown-t, ne tölts ki helyet felesleges kontextussal (model név, tool verziók, file listázások)." 2>/dev/null | head -5)
            if [[ -n "$summary" ]]; then
                echo "$summary" > "$peek_cache"
                echo "$buf_hash" > "$peek_hash_file"
            fi
        ) &>/dev/null &
        # Write actual background PID (not $$) for correct lock detection
        echo $! > "$peek_lock"
        echo $! > "$PEEK_GLOBAL_LOCK"
    fi
    peek=""
    if [[ -f "$peek_cache" ]]; then
        peek=$(cat "$peek_cache" | sed 's/|/∣/g' | tr ' ' "$nbsp" | tr '\n' '|' | sed 's/|/\\n/g; s/\\n$//')
    fi

    # Fallback: window name
    if [[ -z "$topic_text" && "$win_name" != "zsh" && "$win_name" != "claude" && ! "$win_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        topic_text="$win_name"
    fi

    # Build display line with ANSI multi-color
    if (( attached > 0 )); then
        bullet="${A_YELLOW}●"
    else
        bullet="${A_DIM}○"
    fi

    line_body="${A_DIM}[$short_path]"
    if [[ -n "$topic_text" ]]; then
        line_body="$line_body ${A_DIM}» ${A_MAGENTA}$topic_text"
        if [[ -n "$comp_text" ]]; then
            line_body="$line_body $(comp_ansi "$comp_text")${comp_text}%"
        fi
    fi
    # Braille blank (U+2800) prevents SwiftBar from trimming trailing spaces — keeps line wider than alt_line to avoid layout shift
    line="${bullet} ${line_body}${A_RST}  $(printf '\xe2\xa0\x80')"
    alt_line="${bullet} ${line_body} ${A_RED}✕${A_RST}"

    # Badge: completeness %
    badge_param=""
    if [[ -n "$comp_text" ]]; then
        badge_param=" badge=${comp_text}%"
    fi

    # Tooltip param
    tt_param=""
    [[ -n "$peek" ]] && tt_param=" tooltip=$peek"

    # Normal click: focus (attached) or attach (detached)
    if (( attached > 0 )); then
        echo "$line | ansi=true size=13${badge_param}${tt_param} bash=$HELPERS/claude-focus.sh param1=$sess_name terminal=false refresh=true"
    else
        echo "$line | ansi=true size=13${badge_param}${tt_param} bash=$HELPERS/claude-attach.sh param1=$sess_name terminal=false refresh=true"
    fi

    # Alternate (Option held): ✕ replaces bullet (kill + reopen menu)
    echo "${alt_line} | ansi=true size=13 alternate=true bash=$HELPERS/claude-kill.sh param1=$sess_name terminal=false refresh=true"

done < <(TMUX= $TMUX_BIN list-panes -a -F "#{session_name}	#{session_attached}	#{window_name}	#{pane_current_command}	#{pane_current_path}	#{pane_title}	#{pane_id}	#{window_id}" 2>/dev/null)

if ! $has_sessions; then
    echo "No active sessions | size=11 color=#888888 sfimage=moon.zzz"
fi

# ── Other accounts (multi-account mode) ─────────────────

if $MULTI_ACCOUNT; then
    echo "---"
    json_num_file()  { grep -oE "\"$1\":[[:space:]]*[0-9]+" "$2" 2>/dev/null | head -1 | grep -o '[0-9]*$' ; }
    json_str_file()  { grep -oE "\"$1\":[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 | sed "s/\"$1\":[[:space:]]*\"//;s/\"$//" ; }
    while IFS= read -r acct; do
        [[ "$acct" == "$PRIMARY_ACCOUNT" ]] && continue
        acct_file="/tmp/claude-usage-${acct}.json"
        if [[ -f "$acct_file" ]]; then
            apct=$(json_num_file pct "$acct_file")
            aerr=$(json_str_file error "$acct_file")
            if [[ -n "$apct" ]]; then
                if $SHOW_REMAINING; then adisp=$((100 - apct)); else adisp=$apct; fi
                acolor=$(pct_color $adisp)
                echo "${acct}: ${adisp}% | color=$acolor size=12"
            elif [[ -n "$aerr" ]]; then
                echo "${acct}: $aerr | color=#888888 size=12"
            else
                echo "${acct}: -- | color=#888888 size=12"
            fi
        else
            echo "${acct}: no data | color=#888888 size=12"
        fi
    done <<< "$ALL_ACCOUNTS"
fi

# ── Controls ─────────────────────────────────────────────

echo "---"
echo "Refresh now | bash=$POLL_SCRIPT terminal=false refresh=true shortcut=CMD+OPT+R"
echo "Usage chart | bash=$HELPERS/usage-chart.sh terminal=false sfimage=chart.bar.xaxis"
echo "View logs | bash=/usr/bin/open param1=-R param2=$HOME_DIR/.local/share/claude-usage/ terminal=false"
if $MULTI_ACCOUNT; then
    echo "Stop all monitors | bash=/usr/bin/env param1=bash param2=-c param3=\"$TMUX_BIN ls -F '#{session_name}' 2>/dev/null | grep '^claude_usage_mon' | xargs -I{} $TMUX_BIN kill-session -t {}\" terminal=false refresh=true"
else
    echo "Stop monitor | bash=$TMUX_BIN param1=kill-session param2=-t param3=claude_usage_mon terminal=false refresh=true"
fi
