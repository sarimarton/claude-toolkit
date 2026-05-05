# Tmux prompt-marks: numbered chapter separator + OSC 133 prompt marks
# + auto-bookmark stack for "jump back to before last command".
#
# Source from .zshrc (the file is harmless to source outside tmux — it
# returns early if not in an interactive tmux shell):
#
#   [[ -f "$HOME/.config/tmux/prompt-marks.zsh" ]] && source "$HOME/.config/tmux/prompt-marks.zsh"
#
# Plays well with an existing precmd() defined elsewhere — uses
# add-zsh-hook so both run.

[[ -o interactive ]] || return
[[ -z "$TMUX" ]] && return

zmodload zsh/datetime 2>/dev/null

CT_PM_STATE_DIR="${HOME}/.config/claude-toolkit/state"
mkdir -p "$CT_PM_STATE_DIR" 2>/dev/null

_ct_pm_slug() { print -r -- "${TMUX_PANE//\%/}"; }
_ct_pm_counter_file() { print -r -- "${CT_PM_STATE_DIR}/prompt-counter-$(_ct_pm_slug)"; }
_ct_pm_bookmarks_file() { print -r -- "${CT_PM_STATE_DIR}/bookmarks-$(_ct_pm_slug)"; }

_ct_pm_increment_counter() {
  local f n
  f=$(_ct_pm_counter_file)
  if [[ -f $f ]]; then n=$(<"$f"); else n=0; fi
  n=$((n + 1))
  print -r -- "$n" > "$f"
  print -r -- "$n"
}

_ct_pm_peek_counter() {
  local f
  f=$(_ct_pm_counter_file)
  if [[ -f $f ]]; then cat -- "$f"; else print -r -- "0"; fi
}

_ct_pm_separator() {
  local n="$1"
  local ts cwd left cols fill_len fill
  if (( ${+EPOCHSECONDS} )); then
    strftime -s ts "%H:%M:%S" "$EPOCHSECONDS"
  else
    ts=$(date +%H:%M:%S)
  fi
  cwd="${PWD/#$HOME/~}"
  left="── #${n} ${ts}  ${cwd} "
  cols=${COLUMNS:-80}
  fill_len=$((cols - ${#left}))
  (( fill_len < 0 )) && fill_len=0
  fill="${(l:fill_len::─:)}"
  print -P -- "%F{240}${left}${fill}%f"
}

_ct_pm_capture_snapshot() {
  tmux display -p -t "$TMUX_PANE" '#{e|+:#{history_size},#{pane_height}}' 2>/dev/null
}

_ct_pm_save_bookmark() {
  local n="$1" h="$2" cmd="$3"
  local file summary lines
  [[ -z "$n" || -z "$h" ]] && return
  file=$(_ct_pm_bookmarks_file)
  summary="${cmd:0:60}"
  summary="${summary//$'\n'/ }"
  summary="${summary//$'\t'/ }"
  printf '%s\t%s\t%s\n' "$n" "$h" "$summary" >> "$file"
  if [[ -f $file ]]; then
    lines=$(wc -l < "$file")
    if (( lines > 50 )); then
      tail -n 50 "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
  fi
}

# State variables for the precmd/preexec interplay:
#   _ct_pm_pending_n — the counter value for the prompt that's currently
#     waiting for input (set in precmd, unset on shell start). On the NEXT
#     precmd, if no preexec fired in between (= empty Enter), we know that
#     prompt didn't get a bookmark and we save one explicitly with cmd="(empty)".
#   _ct_pm_had_cmd — set by preexec; cleared by precmd. Tells precmd whether
#     a real command ran since last time.
_ct_pm_pending_n=""
_ct_pm_had_cmd=""

_ct_pm_precmd() {
  # If the previous prompt didn't get a bookmark (empty Enter), save one
  # now so that every separator has a corresponding menu entry.
  if [[ -n "$_ct_pm_pending_n" && "$_ct_pm_had_cmd" != "1" ]]; then
    _ct_pm_save_bookmark "$_ct_pm_pending_n" "$(_ct_pm_capture_snapshot)" "(empty)"
  fi
  _ct_pm_had_cmd=""

  local n
  n=$(_ct_pm_increment_counter)
  _ct_pm_pending_n="$n"
  _ct_pm_separator "$n"
  # OSC 133;A — start of prompt (used by tmux next-prompt/previous-prompt)
  printf '\e]133;A\e\\'
}

_ct_pm_preexec() {
  _ct_pm_had_cmd=1
  # OSC 133;C — start of command output
  printf '\e]133;C\e\\'
  _ct_pm_save_bookmark "$(_ct_pm_peek_counter)" "$(_ct_pm_capture_snapshot)" "$1"
}

autoload -U add-zsh-hook
add-zsh-hook precmd _ct_pm_precmd
add-zsh-hook preexec _ct_pm_preexec
