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

export PATH="{{home}}/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ── Menu-bar text style ──────────────────────────────────
# The condensed font for the menu-bar title line. Change it in ONE place here.
# MENUBAR_STYLE is the full SwiftBar param suffix for the standard size-12 title;
# the boot placeholder uses MENUBAR_FONT with its own smaller size.
MENUBAR_FONT="RobotoCondensed-Regular"
MENUBAR_STYLE="ansi=true size=10 font=$MENUBAR_FONT"

# ── Cache-first rendering — the display path NEVER does slow work ──
# SwiftBar runs this script in two situations: every 10s (background tick) and on
# every dropdown open (refreshOnOpen, blocking). The full render below is heavy,
# especially at boot — it enumerates tmux panes (slow while tmux-resurrect is still
# restoring them), runs git/gh update checks, and shells out to auto-dev. If that
# heavy render ran synchronously on a dropdown open, two bad things happened:
#   1. The click felt slow ("Starting Claude…" lingered for seconds).
#   2. When the slow run finally finished, SwiftBar rebuilt the *already-open*
#      NSMenu, which dismisses it — the menu "disappeared" out from under the click.
# Fix: the foreground (display) invocation ONLY ever serves the cache, and kicks the
# refresh off in a detached background process. SwiftBar therefore always gets
# instant output and never rebuilds the open menu mid-interaction. The heavy render
# runs under CLAUDE_MENU_RENDER=1 and writes only to the cache, never to SwiftBar.
_MENU_CACHE="/tmp/claude-menu-raw.txt"
_MENU_CACHE_TTL=9
_RENDER_LOCK="/tmp/claude-menu-render.lock"

_spawn_bg_render() {
    # One render at a time — ticks/clicks during an in-flight render are no-ops.
    # Detach from SwiftBar's stdout pipe (>/dev/null) so the foreground can exit
    # immediately; SwiftBar treats the plugin as done once its pipe hits EOF.
    if [[ -f "$_RENDER_LOCK" ]] && kill -0 "$(cat "$_RENDER_LOCK" 2>/dev/null)" 2>/dev/null; then
        return
    fi
    CLAUDE_MENU_RENDER=1 bash "$0" >/dev/null 2>&1 &
    echo $! > "$_RENDER_LOCK"
}

if [[ "$CLAUDE_MENU_RENDER" != "1" ]]; then
    # ── Display path: serve cache, refresh in background, exit fast ──
    # Serve the cache regardless of age (a stale render already carries its own ⚠
    # markers); a slow synchronous render is never worth a dismissed/vanished menu.
    if [[ -s "$_MENU_CACHE" ]]; then
        cat "$_MENU_CACHE"
        _cache_age=$(( $(date +%s) - $(stat -f %m "$_MENU_CACHE" 2>/dev/null || echo 0) ))
        (( _cache_age >= _MENU_CACHE_TTL )) && _spawn_bg_render
        exit 0
    fi
    # No cache yet (fresh boot / cleared /tmp): show a lightweight placeholder so the
    # icon appears instantly, and build the real menu in the background. The next
    # tick (≤10s) serves the real cache. Emitting non-empty output here is essential
    # — SwiftBar removes the menu-bar item entirely on empty stdout.
    printf '\033[38;5;214m✻ \033[38;5;243m…\033[0m | ansi=true size=10 font=%s\n' "$MENUBAR_FONT"
    _spawn_bg_render
    exit 0
fi

# ── Render path (CLAUDE_MENU_RENDER=1): build the menu and publish it ──
# Reached only via _spawn_bg_render, detached from SwiftBar's stdout pipe. Output
# goes to a per-PID temp that is promoted to the live cache only when non-empty, so
# a killed or raced writer can never publish a 0-byte cache (which SwiftBar would
# render as a vanished icon).
trap 'rm -f "$_RENDER_LOCK"' EXIT
_MENU_CACHE_TMP="$_MENU_CACHE.$$.tmp"
exec > >(tee "$_MENU_CACHE_TMP" >/dev/null; if [[ -s "$_MENU_CACHE_TMP" ]]; then mv "$_MENU_CACHE_TMP" "$_MENU_CACHE"; else rm -f "$_MENU_CACHE_TMP"; fi)

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
  YQ={{yq}}
  primary=$($YQ -r '(.accounts[] | select(.primary == true) | .name) // .accounts[0].name' "$CONFIG_FILE" 2>/dev/null)
  all_names=$($YQ -r '.accounts[].name' "$CONFIG_FILE" 2>/dev/null)
  account_info=""
  if [ -n "$primary" ] && [ -n "$all_names" ]; then
    account_info=$(printf '%s\n%s' "$primary" "$all_names")
  fi
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

json_str()  { grep -oE "[,{[:space:]]\"$1\":[[:space:]]*\"[^\"]*\"" "$USAGE_FILE" 2>/dev/null | head -1 | sed "s/.*\"$1\":[[:space:]]*\"//;s/\"$//" ; }
json_num()  { grep -oE "[,{[:space:]]\"$1\":[[:space:]]*[0-9]+" "$USAGE_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*$' ; }

# ── Auto-poll: trigger refresh if data is stale ──
# Interval is read live from config.yaml each render (modules.usageMonitor
# .pollIntervalSeconds, default 300), so editing the config takes effect without a
# reinstall. Each poll recreates the monitor's claude session from scratch (the
# long-lived session freezes its "Current session" value after ~1h), so we poll less
# often to keep the per-poll ~4s claude startup churn down. /usage is a local slash
# command (no model inference), so recreating costs startup time, not tokens.
POLL_INTERVAL=$({{yq}} -r '.modules.usageMonitor.pollIntervalSeconds // 300' "$CONFIG_FILE" 2>/dev/null)
case "$POLL_INTERVAL" in ''|*[!0-9]*) POLL_INTERVAL=300 ;; esac
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
        ( bash "$POLL_SCRIPT"; rm -f "$POLL_LOCK" ) &>/dev/null &
        # Write actual background PID (not $$) for correct lock detection
        echo $! > "$POLL_LOCK"
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
last_success_ts=$(json_num last_success_ts)

# Stale detection: a poll cycle (claude restart + /usage + parse) takes up to ~15s,
# so fresh data is at most POLL_INTERVAL+15s old just before the next poll. Flag as
# stale only past ~2 missed cycles, so normal data is never falsely marked. Without
# this guard the menu can show a green "92%" while the real session usage is 33%.
STALE_THRESHOLD=$(( POLL_INTERVAL * 2 + 60 ))
is_stale=false
stale_age_min=""
now_check=$(date +%s)
# Only trust last_success_ts (set by the python parser on a real parse).
# Never fall back to ts — ts is bumped on every poll, including failure paths
# where pct is preserved from prev without a real parse, which would mask staleness.
if [[ -n "$last_success_ts" ]]; then
    age_s=$(( now_check - last_success_ts ))
    if (( age_s > STALE_THRESHOLD )); then
        is_stale=true
        stale_age_min=$(( age_s / 60 ))
    fi
elif [[ -n "$pct" ]]; then
    # We have a pct but no last_success_ts — either pre-rollout JSON, or the
    # parser preserved prev.pct without a real parse. Either way, do not trust it.
    is_stale=true
fi
# If the session reset already passed, the stored pct belongs to a previous window.
if [[ -n "$reset_ts" ]] && (( reset_ts < now_check )); then
    is_stale=true
fi

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
        # pct can exceed 100 when you're over the session limit (extra-budget
        # mode reports e.g. 101% used), which would make "remaining" go negative
        # and the menu show "-1%". Clamp to 0.
        display_pct=$((100 - pct))
        (( display_pct < 0 )) && display_pct=0
    else
        display_pct=$pct
    fi
    if [[ "$error" == "usage_unavailable" ]] || $is_stale; then
        pct_a="$A_DIM"  # stale data → gray
    else
        pct_a=$(pct_ansi $display_pct)
    fi
    title="${A_LOGO}✻ ${pct_a}${display_pct}%"
    $is_stale && title="$title${A_YELLOW}⚠"
    $weekly_capped && title="$title${A_YELLOW}W"
    [[ -n "$mins_left" ]] && title="$title ${A_DIM}($(format_time $mins_left))"
    $MULTI_ACCOUNT && title="$title ${A_DIM}$PRIMARY_ACCOUNT"
    echo "${title}${A_RST} | $MENUBAR_STYLE"
elif [[ "$error" == "usage_unavailable" ]]; then
    echo "${A_LOGO}✻ ${A_YELLOW}⚠${A_RST} | $MENUBAR_STYLE"
elif [[ -n "$phase" && -z "$error" ]]; then
    # Refreshing… spinner — but check that the phase isn't stuck
    age_phase=$(( now_check - ${ts:-0} ))
    if [[ -n "$ts" ]] && (( age_phase > STALE_THRESHOLD )); then
        # Phase has not progressed for >5min — poll is likely stuck or crashed
        echo "${A_LOGO}✻ ${A_DIM}stuck ${A_YELLOW}⚠${A_RST} | $MENUBAR_STYLE"
    else
        label="$phase"
        case "$phase" in
            session) label="Checking session" ;; claude) label="Checking Claude" ;;
            start)   label="Starting Claude"  ;; restart) label="Restarting" ;;
            send)    label="Sending /usage"   ;; wait) label="Waiting" ;;
            parse)   label="Parsing" ;;
        esac
        echo "${A_LOGO}✻ ${A_DIM}${label}…${A_RST} | $MENUBAR_STYLE"
    fi
else
    echo "${A_LOGO}✻ ${A_DIM}--${A_RST} | $MENUBAR_STYLE"
fi

echo "---"

# ── Update check ─────────────────────────────────────────

INSTALL_DIR="{{repo_dir}}"
UPDATE_CACHE="/tmp/claude-toolkit-update-check.json"
UPDATE_CACHE_TTL=60  # 1 minute — near-realtime; gh api gives 5000 req/h so this is cheap

_check_update() {
    local remote_sha
    # Prefer authenticated gh (5000 req/h) so we can poll often; the unauthenticated
    # GitHub API is capped at 60 req/h, which is what forced the old long TTL.
    remote_sha=$(gh api repos/sarimarton/claude-toolkit/commits/main --jq '.sha' 2>/dev/null | grep -oE '^[0-9a-f]{40}$')
    if [[ -z "$remote_sha" ]]; then
        remote_sha=$(curl -sf --max-time 5 \
            "https://api.github.com/repos/sarimarton/claude-toolkit/commits/main" \
            2>/dev/null | grep -m1 '"sha"' | grep -oE '[0-9a-f]{40}' | head -1)
    fi
    [[ -z "$remote_sha" ]] && return
    local ts
    ts=$(date +%s)
    printf '{"sha":"%s","ts":%s}\n' "$remote_sha" "$ts" > "$UPDATE_CACHE"
}

_maybe_refresh_update_cache() {
    local cache_age=99999
    if [[ -f "$UPDATE_CACHE" ]]; then
        local cache_ts
        cache_ts=$(grep -oE '"ts":[0-9]+' "$UPDATE_CACHE" | grep -oE '[0-9]+')
        [[ -n "$cache_ts" ]] && cache_age=$(( $(date +%s) - cache_ts ))
    fi
    if (( cache_age > UPDATE_CACHE_TTL )); then
        ( _check_update ) &>/dev/null &
    fi
}

_maybe_refresh_update_cache

if [[ -f "$UPDATE_CACHE" && -d "$INSTALL_DIR/.git" ]]; then
    remote_sha=$(grep -oE '"sha":"[0-9a-f]{40}"' "$UPDATE_CACHE" | grep -oE '[0-9a-f]{40}' | head -1)
    local_sha=$(git -C "$INSTALL_DIR" rev-parse HEAD 2>/dev/null)
    if [[ -n "$remote_sha" && -n "$local_sha" && "$remote_sha" != "$local_sha" ]]; then
        echo "⬆ Update available | color=#0a84ff size=13 bash=$HELPERS/claude-toolkit-update.sh terminal=false refresh=true"
    fi
fi

# ── Usage details ────────────────────────────────────────

if [[ -n "$pct" ]]; then
    remaining_label=$($SHOW_REMAINING && echo "remaining" || echo "used")
    # When weekly is capped, show actual session % on the status line too
    if $weekly_capped; then
        if $SHOW_REMAINING; then session_display=$((100 - pct)); (( session_display < 0 )) && session_display=0; else session_display=$pct; fi
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
    elif $is_stale; then
        if [[ -n "$reset_ts" ]] && (( reset_ts < now_check )); then
            status_line="$status_line · ⚠ stale: window expired"
        elif [[ -n "$stale_age_min" ]]; then
            status_line="$status_line · ⚠ stale: no fresh parse in ${stale_age_min}m"
        else
            status_line="$status_line · ⚠ stale"
        fi
    elif [[ -n "$phase" ]]; then
        status_line="$status_line · refreshing…"
    fi
    echo "${A_DIM}${status_line}${A_RST} | ansi=true size=13"
    # Weekly usage line (show when data available and not already shown in main line)
    if [[ -n "$weekly_pct" ]] && ! $weekly_capped; then
        if $SHOW_REMAINING; then weekly_display=$((100 - weekly_pct)); (( weekly_display < 0 )) && weekly_display=0; else weekly_display=$weekly_pct; fi
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
        comp_text=$(echo "$topic_line" | sed -n 's/.*\$pct:[[:space:]]*\([0-9]*\).*/\1/p')
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

    # Native recap shortcut: Claude Code writes "※ recap: ... (disable recaps in /config)"
    # into the pane buffer. When a fresh one is present we use it verbatim as the peek
    # (it comes from the main model with full session context) and skip the haiku call.
    # The recap is terminal-wrapped across multiple lines, so we join the marker→tail span.
    recap=$(echo "$pane_buf" | awk '
        /※[[:space:]]*recap:/ { buf=$0; cap=1; next }
        cap {
            buf=buf " " $0
            if ($0 ~ /\(disable recaps in \/config\)/) { last=buf; cap=0 }
        }
        END { if (last != "") print last; else if (cap && buf != "") print buf }
    ' | sed -E 's/.*※[[:space:]]*recap:[[:space:]]*//; s/[[:space:]]*\(disable recaps in \/config\)[[:space:]]*$//; s/[[:space:]]+/ /g; s/[[:space:]]*$//')
    # Locality guard: only trust the recap if it sits near the buffer bottom (not an
    # old, scrolled-past one above fresh activity).
    if [[ -n "$recap" ]]; then
        lines_after=$(echo "$pane_buf" | awk '/\(disable recaps in \/config\)/ { n=NR } END { print NR-n }')
        if (( lines_after <= 8 )); then
            recap_hash=$(echo "$recap" | md5 -q 2>/dev/null || echo "$recap" | md5sum 2>/dev/null | cut -d' ' -f1)
            if [[ "$recap_hash" != "$old_hash" ]]; then
                echo "$recap" > "$peek_cache"
                echo "$recap_hash" > "$peek_hash_file"
            fi
            old_hash="$recap_hash"
            buf_hash="$recap_hash"
        fi
    fi

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
        bullet="${A_YELLOW}●"   # attached → filled yellow
    else
        bullet="${A_YELLOW}○"   # detached but alive → hollow yellow
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
        echo "$line | ansi=true size=13${badge_param}${tt_param} bash=$HELPERS/claude-focus.sh param1=$sess_name param2=$window_id terminal=false refresh=true"
    else
        echo "$line | ansi=true size=13${badge_param}${tt_param} bash=$HELPERS/claude-attach.sh param1=$sess_name terminal=false refresh=true"
    fi

    # Alternate (Option held): ✕ replaces bullet (kill + reopen menu)
    echo "${alt_line} | ansi=true size=13 alternate=true bash=$HELPERS/claude-kill.sh param1=$sess_name terminal=false refresh=true"

done < <(TMUX= $TMUX_BIN list-panes -a -F "#{session_name}	#{session_attached}	#{window_name}	#{pane_current_command}	#{pane_current_path}	#{pane_title}	#{pane_id}	#{window_id}" 2>/dev/null)

# ── Dead (restorable) sessions — rebooted/crashed panes ──
# tmux-resurrect brings the "✻ topic" windows back after a reboot, but Claude is
# gone, so those panes run a plain shell and fall out of the live loop above. List
# them with a hollow gray ○ and resume on click using the UUID the Stop hook
# recorded, matched by (session, window-name).
#
# A matching row is only worth showing if its UUID still has a session file on
# disk — otherwise `claude --resume <uuid>` greets the user with "No conversation
# found". The Stop hook now keeps one row per (session, window-name), but older
# indexes piled up many rows (one per rotated UUID), most of them ephemeral with
# no surviving .jsonl. So we walk the matching rows newest-first and pick the
# first UUID whose <uuid>.jsonl exists anywhere under the project store; if none
# survives, the topic is unrecoverable and we skip it entirely (no dead ○).
RESUME_INDEX="{{state_dir}}/resume-index.tsv"
PROJ_ROOT="$HOME_DIR/.claude/projects"
if [[ -f "$RESUME_INDEX" ]]; then
    while IFS=$'\t' read -r sess_name attached win_name proc path pane_id window_id; do
        [[ "$proc" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue   # alive → already listed above
        [[ "$sess_name" == "claude_usage_mon" ]] && continue
        case "$win_name" in "✻ "*) ;; *) continue ;; esac        # only topic windows
        case "$seen_windows" in *"|$window_id|"*) continue ;; esac
        seen_windows="${seen_windows}|${window_id}|"

        # Candidate UUIDs for this (session, window-name), newest row last.
        uuid=""
        while IFS= read -r cand; do
            [[ -z "$cand" ]] && continue
            if compgen -G "$PROJ_ROOT"/*/"$cand".jsonl >/dev/null 2>&1; then
                uuid="$cand"   # keep scanning; newer survivors override
            fi
        done < <(awk -F'\t' -v s="$sess_name" -v w="$win_name" '$1==s && $2==w {print $3}' "$RESUME_INDEX")
        [[ -z "$uuid" ]] && continue   # no surviving session file → unrecoverable
        has_sessions=true

        short_path="${path/#$HOME_DIR/\~}"
        topic_text="${win_name#✻ }"
        line_body="${A_DIM}[$short_path] ${A_DIM}» ${A_MAGENTA}${topic_text}"
        line="${A_DIM}○ ${line_body}${A_RST}  $(printf '\xe2\xa0\x80')"
        echo "$line | ansi=true size=13 tooltip=Resume bash=$HELPERS/claude-resume.sh param1=$sess_name param2=$pane_id param3=$uuid terminal=false refresh=true"

        # Alternate (Option held): ✕ cleans up — drop the index rows for this
        # (session, window-name) and close the resurrected shell pane, so the dead
        # topic disappears from the menu entirely.
        cleanup_line="${A_DIM}○ ${line_body} ${A_RED}✕${A_RST}"
        echo "$cleanup_line | ansi=true size=13 alternate=true tooltip=Remove bash=$HELPERS/claude-resume-cleanup.sh param1=$sess_name param2=$win_name param3=$pane_id terminal=false refresh=true"
    done < <(TMUX= $TMUX_BIN list-panes -a -F "#{session_name}	#{session_attached}	#{window_name}	#{pane_current_command}	#{pane_current_path}	#{pane_id}	#{window_id}" 2>/dev/null)
fi

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
                if $SHOW_REMAINING; then adisp=$((100 - apct)); (( adisp < 0 )) && adisp=0; else adisp=$apct; fi
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

# ── Optional module extensions (post-sessions) ───────────
if [[ -f "$HELPERS/auto-dev-section.sh" ]]; then
  bash "$HELPERS/auto-dev-section.sh"
fi

# ── Controls ─────────────────────────────────────────────

echo "---"
echo "Tools"
echo "-- Usage chart | bash=$HELPERS/usage-chart.sh terminal=false sfimage=chart.bar.xaxis"
echo "-- Edit config… | bash=$HELPERS/edit-config.sh terminal=false refresh=false sfimage=gearshape"
if [[ -f "$HELPERS/auto-dev-install.sh" ]]; then
  echo "-- Auto-dev"
  echo "---- Install Auto-dev to repo… | bash=$HELPERS/auto-dev-install.sh terminal=false refresh=false"
fi
echo "-- View logs | bash=/usr/bin/open param1=-R param2={{state_dir}}/usage/ terminal=false"
if $MULTI_ACCOUNT; then
    echo "-- Stop all monitors | bash=/usr/bin/env param1=bash param2=-c param3=\"$TMUX_BIN ls -F '#{session_name}' 2>/dev/null | grep '^claude_usage_mon' | xargs -I{} $TMUX_BIN kill-session -t {}\" terminal=false refresh=true"
else
    echo "-- Stop monitor | bash=$TMUX_BIN param1=kill-session param2=-t param3=claude_usage_mon terminal=false refresh=true"
fi

