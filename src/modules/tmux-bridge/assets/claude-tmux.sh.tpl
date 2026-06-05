#!/usr/bin/env bash
# claude-tmux — a drop-in replacement for `claude -p` that runs *interactive*
# Claude Code inside a throwaway tmux session, injects the prompt, and parses the
# answer back out — with ZERO model inference of its own.
#
# WHY THIS EXISTS
#   Headless invocations (`claude -p`, GitHub-Actions / "cloud" runs) bill against
#   a separate metered credit pool, not the interactive subscription bucket. From
#   2026-06-15 that split makes the auto-dev pipeline (which calls `claude -p`)
#   draw from the wrong pool. By driving a *real interactive* Claude TUI
#   programmatically instead, the work is billed as interactive usage — i.e. it
#   consumes the subscription bucket like any hand-typed session would.
#
# HOW IT WORKS  (all steps are deterministic — no LLM is used to drive or parse)
#   1. Spawn a fresh, isolated tmux session running `claude --dangerously-skip-permissions`.
#   2. Wrap the caller's prompt with an instruction to emit its answer between two
#      fixed sentinel markers (and, for JSON mode, to emit a single JSON object).
#   3. Inject the prompt with `send-keys -l` (literal burst — avoids the slash /
#      autocomplete dropdown), then Enter.
#   4. Stream every byte the pane writes via `pipe-pane` to a raw log (capture-pane
#      only reads the *settled* grid and would miss in-flight repaints).
#   5. Detect completion: the closing sentinel appears in the raw stream (primary),
#      or the TUI returns to the input prompt with the spinner gone (backup), or a
#      timeout fires.
#   6. Extract the text between the sentinels, strip ANSI/TUI noise, and print it.
#      In JSON mode, wrap it as {"structured_output": <obj>} so callers that did
#      `claude -p --output-format json --json-schema` (e.g. auto-dev) parse it with
#      `jq '.structured_output…'` exactly as before — byte-compatible drop-in.
#
# USAGE
#   claude-tmux -p "<prompt>" [--model <id>] [--output-format json]
#               [--json-schema '<schema>'] [--timeout <secs>] [--cwd <dir>]
#   Prompt may also be supplied on stdin if -p is omitted.
#
# EXIT CODES
#   0 success · 1 generic failure · 2 claude failed to start · 3 timeout waiting
#   for completion · 4 JSON requested but no valid JSON object found.

set -uo pipefail
unset TMUX

TMUX_BIN={{tmux}}
CLAUDE_DEFAULT={{claude}}
STATE_DIR="{{state_dir}}/tmux-bridge"

# Prefer the TCC-stable launcher when the stable-claude-bin module is installed,
# matching how auto-dev resolves its CLAUDE_BIN; fall back to the version symlink.
CLAUDE_BIN="{{scripts_dir}}/claude-stable"; [ -x "$CLAUDE_BIN" ] || CLAUDE_BIN="$CLAUDE_DEFAULT"

# ── Argument parsing (mirrors the `claude -p` surface we actually use) ──────────
PROMPT=""
MODEL=""
OUTPUT_FORMAT="text"
JSON_SCHEMA=""
TIMEOUT=240
CWD="$HOME"
PROMPT_SET=false
KEEP_SESSION=false   # --keep-session: leave the tmux session + raw grid alive on exit

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--print)        PROMPT="${2-}"; PROMPT_SET=true; shift 2 ;;
    --model)           MODEL="${2-}"; shift 2 ;;
    --output-format)   OUTPUT_FORMAT="${2-}"; shift 2 ;;
    --json-schema)     JSON_SCHEMA="${2-}"; shift 2 ;;
    --timeout)         TIMEOUT="${2-}"; shift 2 ;;
    --cwd)             CWD="${2-}"; shift 2 ;;
    # Diagnostic: do NOT kill the tmux session on return, and keep the captured raw
    # grid. Lets you `tmux attach` to inspect the live TUI state after a run (e.g.
    # to see exactly what Claude rendered when completion/parsing misbehaved). The
    # session name + attach command + raw-log path are printed to stderr on exit.
    --keep-session)    KEEP_SESSION=true; shift ;;
    # Accept-and-ignore flags the caller may pass through from the `claude -p`
    # call site; they are meaningless for an interactive session but must not
    # break the drop-in contract.
    --dangerously-skip-permissions) shift ;;
    --) shift; break ;;
    -*) shift ;;   # unknown flag → ignore, stay tolerant
    *)  if ! $PROMPT_SET; then PROMPT="$1"; PROMPT_SET=true; fi; shift ;;
  esac
done

# Prompt via stdin if not given as an argument (so `… | claude-tmux` works).
if ! $PROMPT_SET && [ ! -t 0 ]; then
  PROMPT="$(cat)"
  PROMPT_SET=true
fi

if [ -z "$PROMPT" ]; then
  echo "claude-tmux: no prompt (use -p '<prompt>' or pipe on stdin)" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

# Unique session + log per invocation so concurrent callers never collide.
# Math-only uniqueness (PID + nanoseconds) — no randomness needed.
UNIQ="$$_$(date +%s%N)"
# Dotted, underscore-free variant for the markdown-safe sentinels (an "_" would be
# read as markdown emphasis by the TUI renderer and could mangle the marker).
UNIQ_DOT="$(printf '%s' "$UNIQ" | tr '_' '.')"
SESSION="claude_tmux_${UNIQ}"
RAW_LOG="$STATE_DIR/raw_${UNIQ}.log"

# Sentinels: long, unlikely-to-collide tokens the model prints around its answer;
# we slice on them.
#
# MARKDOWN-SAFE by construction: NO <, >, `, *, _, #, ~, [, ] — the Claude TUI
# renders the answer through a markdown layer, and a token like "<<<…>>>" gets
# eaten/collapsed (observed live: it displayed as "<<>>", so the literal marker
# never reached the stream and completion never fired). Plain uppercase + digits +
# dots survive rendering verbatim. The leading "ZZ" + dotted shape makes accidental
# collision with real answer text effectively impossible.
BEGIN_MARK="ZZCLAUDETMUX.BEGIN.${UNIQ_DOT}.ZZ"
END_MARK="ZZCLAUDETMUX.END.${UNIQ_DOT}.ZZ"

cleanup() {
  # --keep-session (diagnostic): leave the session running and the raw grid on disk,
  # and tell the user how to attach. Everything else cleans up as usual.
  if $KEEP_SESSION; then
    {
      echo "claude-tmux: --keep-session — left session alive for inspection."
      echo "  attach:  $TMUX_BIN attach -t $SESSION"
      echo "  kill:    $TMUX_BIN kill-session -t $SESSION"
      echo "  raw log: $RAW_LOG"
    } >&2
    return
  fi
  $TMUX_BIN kill-session -t "$SESSION" 2>/dev/null || true
  # CLAUDE_TMUX_KEEP_RAW=1 preserves the captured grid for diagnosis (default: clean up).
  [ -n "${CLAUDE_TMUX_KEEP_RAW:-}" ] || rm -f "$RAW_LOG" 2>/dev/null || true
}
trap cleanup EXIT

# ── Build the wrapped prompt ────────────────────────────────────────────────────
# We instruct the model to delimit its answer with the sentinels. In JSON mode we
# additionally pin it to a single JSON object (and pass the schema as guidance —
# interactive Claude has no --json-schema validation, so the schema is conveyed in
# the prompt and validated by us afterwards).
build_wrapped_prompt() {
  # IMPORTANT: mention each marker EXACTLY ONCE. The TUI echoes this prompt back
  # into the grid, so every literal occurrence here reappears in the captured grid.
  # Completion/extraction count marker occurrences to tell the echoed prompt apart
  # from the real answer (the answer adds the 2nd occurrence of each), so a 2nd
  # mention here would desync that count. Phrase the rule without repeating END.
  printf '%s\n' "$PROMPT"
  printf '\n'
  printf -- '---\n'
  printf 'OUTPUT PROTOCOL (a script parses this, not a human; follow EXACTLY):\n'
  printf 'Wrap your entire answer between two marker lines and print nothing outside them.\n'
  printf 'First line, alone: %s\n' "$BEGIN_MARK"
  printf 'Then your answer.\n'
  printf 'Last line, alone: %s\n' "$END_MARK"
  if [ "$OUTPUT_FORMAT" = "json" ]; then
    printf 'Between the markers, emit a single valid JSON object and nothing else — no prose, no markdown, no code fences.\n'
    if [ -n "$JSON_SCHEMA" ]; then
      printf 'The JSON object must conform to this JSON Schema:\n%s\n' "$JSON_SCHEMA"
    fi
  fi
}

# ── Launch an interactive Claude session ────────────────────────────────────────
$TMUX_BIN kill-session -t "$SESSION" 2>/dev/null || true
$TMUX_BIN new-session -d -s "$SESSION" -x 220 -y 50 -c "$CWD"

claude_cmd="$CLAUDE_BIN --dangerously-skip-permissions"
[ -n "$MODEL" ] && claude_cmd="$claude_cmd --model '$MODEL'"

$TMUX_BIN send-keys -t "$SESSION" "$claude_cmd" Enter
sleep 1
$TMUX_BIN clear-history -t "$SESSION" 2>/dev/null || true

# Wait for the TUI to come up (trust prompt → Enter; input prompt ❯ → ready).
claude_up=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1.5
  pane=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null || true)
  if printf '%s' "$pane" | grep -q "trust this folder"; then
    $TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null || true
    sleep 2
  fi
  if printf '%s' "$pane" | grep -qE '^❯|bypass permissions|⏵⏵'; then
    claude_up=true; break
  fi
done

if ! $claude_up; then
  diag=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -v '^$' | tail -10)
  echo "claude-tmux: Claude failed to start" >&2
  printf '%s\n' "$diag" >&2
  exit 2
fi

# ── Inject the prompt ───────────────────────────────────────────────────────────
# Clear any residual input (C-u, never Escape — Escape opens the wrong panel).
$TMUX_BIN send-keys -t "$SESSION" C-u 2>/dev/null || true
sleep 0.3

# Deliver the prompt via tmux bracketed paste, NOT send-keys -l.
#
# The prompt is multi-line (the output-protocol block). send-keys -l streams the
# bytes raw, so each embedded newline is seen by the Claude TUI as a separate
# line-submit — the prompt fragments and the final Enter submits only the last
# line (observed live: the prompt sat half-typed in the input box, never sent).
#
# load-buffer + paste-buffer -p wraps the text in bracketed-paste escapes
# (ESC[200~ … ESC[201~). The Claude TUI, like any modern line editor, treats a
# bracketed paste as ONE literal insertion — embedded newlines become part of the
# input instead of submitting it. A single explicit Enter afterwards submits the
# whole multi-line prompt at once.
WRAPPED="$(build_wrapped_prompt)"
printf '%s' "$WRAPPED" | $TMUX_BIN load-buffer -b claude_tmux_prompt - 2>/dev/null
$TMUX_BIN paste-buffer -p -b claude_tmux_prompt -t "$SESSION" 2>/dev/null
$TMUX_BIN delete-buffer -b claude_tmux_prompt 2>/dev/null || true
sleep 0.5
$TMUX_BIN send-keys -t "$SESSION" Enter 2>/dev/null || true

# ── Wait for completion ─────────────────────────────────────────────────────────
# Source of truth is the tmux GRID (capture-pane -p -S -<n>), NOT a pipe-pane
# stream. Why: Claude renders an answer as a settled ⏺ block that "snaps" into the
# grid in one repaint rather than streaming byte-by-byte; pipe-pane catches the
# in-flight frames and routinely MISSES the final block, so a JSON answer's BEGIN
# would land but END/body never would (observed live: raw stream held only BEGIN,
# while capture-pane showed the full ⏺ BEGIN / {json} / END block). The grid always
# holds the settled answer, so we poll it directly.
#
# Completion = the END marker is present in the grid. The grid also contains the
# echoed prompt (which carries the marker literals as instruction text), but
# extraction takes the LAST begin→end pair, so the echo can't be mistaken for the
# answer. We snapshot a generous scrollback so a long answer that scrolled the
# input prompt off-screen is still captured in full.
CAPTURE_LINES=2000
grid_snapshot() {
  $TMUX_BIN capture-pane -t "$SESSION" -p -S -"$CAPTURE_LINES" 2>/dev/null || true
}
# Count END-marker occurrences in the grid. The echoed prompt contributes exactly
# ONE (the protocol mentions END once); the real answer contributes the SECOND. So
# completion = END appears at least TWICE. This is what lets us ignore the prompt
# echo without any timing guesswork: until the answer's own END lands, the count
# stays at 1. (whitespace-tolerant, to survive a column-edge wrap of the marker.)
grid_end_count() {
  printf '%s' "$1" | python3 -c '
import sys, re
raw = sys.stdin.read()
mark = sys.argv[1]
n = raw.count(mark)
if n == 0:
    n = len(re.findall(r"\s*".join(re.escape(c) for c in mark), raw))
print(n)
' "$END_MARK" 2>/dev/null || echo 0
}

START=$SECONDS
done_rc=3
while [ $(( SECONDS - START )) -lt "$TIMEOUT" ]; do
  if [ "$(grid_end_count "$(grid_snapshot)")" -ge 2 ]; then
    done_rc=0; break
  fi
  sleep 0.5
done

# Take a FINAL, stable snapshot for the parser — not the loop's last in-flight
# read. The completion check may fire on a frame that is mid-repaint (the answer's
# END just landed but the body line is being rewritten), so a brief settle plus a
# fresh capture guarantees the parser sees the fully-rendered ⏺ answer block. We
# re-snapshot until the END count is stable across two reads (or a short cap).
if [ "$done_rc" = 0 ]; then
  GRID="$(grid_snapshot)"
  for _ in 1 2 3 4; do
    sleep 0.4
    GRID2="$(grid_snapshot)"
    [ "$(grid_end_count "$GRID2")" -ge 2 ] && GRID="$GRID2"
    [ "$GRID2" = "$GRID" ] && break
    GRID="$GRID2"
  done
  printf '%s' "$GRID" > "$RAW_LOG"
else
  grid_snapshot > "$RAW_LOG"
fi

if [ "$done_rc" = 3 ]; then
  diag=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null | grep -v '^$' | tail -15)
  echo "claude-tmux: timed out after ${TIMEOUT}s waiting for completion" >&2
  printf '%s\n' "$diag" >&2
  exit 3
fi

# ── Extract + emit ──────────────────────────────────────────────────────────────
# Delegate to parse_answer.py (a standalone, unit-tested module — see
# test_parse_answer.py). It slices the answer out from between the sentinels,
# strips the TUI chrome deterministically, and in JSON mode validates the object
# against JSON_SCHEMA (a dependency-free subset check: type/enum/required) before
# wrapping it as {"structured_output": …}. Exit: 0 ok · 1 no sentinels · 4 JSON
# invalid or schema mismatch.
export BEGIN_MARK END_MARK OUTPUT_FORMAT JSON_SCHEMA
python3 "{{scripts_dir}}/claude-tmux-parse.py" "$RAW_LOG"
emit_rc=$?

exit $emit_rc
