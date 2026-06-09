#!/usr/bin/env bash
# ax-context — read the focused app's visible TEXT via the macOS Accessibility API
# (AppleScript / System Events). Vendor-independent (no Hammerspoon, no compiled
# binary). Synchronous: prints the on-screen text to stdout and exits.
#
# This is the non-tmux analogue of `tmux capture-pane -p`. For Electron apps like
# Claude Desktop the conversation text is NOT reachable via AXFocusedUIElement
# (that only yields the input placeholder "Write a message…"), and the AXWebArea
# nodes expose no children to a recursive walk. The trick (found by live probing):
# ask System Events for `entire contents of front window` — a FLAT list that DOES
# surface the rendered AXStaticText leaves — then filter to AXStaticText values.
# Native (non-Electron) apps fall back to the focused element's AXValue.
#
# The raw AX dump is heavily contaminated with UI chrome (sidebar, Recents list,
# per-message action buttons, mode tabs); the shell wrapper strips a known blocklist,
# drops the "Claude responded:"/"You said:" summary lines that duplicate the bodies,
# and dedupes consecutive repeats. Degrades gracefully to empty output (exit 0).
#
# Env:
#   DICT_OSASCRIPT_BIN   override the osascript binary (tests inject a stub)
#   AX_CONTEXT_MAXBYTES  output byte cap (default 4096; keeps the TAIL)
set -uo pipefail
export PATH="/opt/homebrew/bin:$HOME/homebrew/bin:/usr/local/bin:$PATH"

OSA="${DICT_OSASCRIPT_BIN:-osascript}"
MAXBYTES="${AX_CONTEXT_MAXBYTES:-4096}"

# AppleScript: flatten the front window and collect AXStaticText values; if that is
# empty (native app whose text is in a focused field), fall back to the focused
# element's AXValue. Every attribute read is guarded so one bad node can't abort.
read_ax() {
  "$OSA" <<'APPLESCRIPT' 2>/dev/null
on run
  set frontApp to ""
  tell application "System Events"
    try
      set frontApp to name of first application process whose frontmost is true
    end try
  end tell
  if frontApp is "" then return ""

  set acc to {}
  try
    tell application "System Events"
      tell process frontApp
        set els to entire contents of front window
        set n to 0
        repeat with el in els
          set n to n + 1
          if n > 4000 then exit repeat
          try
            if (role of el) is "AXStaticText" then
              set v to value of el
              if v is not missing value then
                set vt to (v as text)
                if vt is not "" then set end of acc to vt
              end if
            end if
          end try
        end repeat
      end tell
    end tell
  end try

  -- Fallback for native apps: focused element value.
  if (count of acc) is 0 then
    try
      tell application "System Events"
        tell process frontApp
          set fe to value of attribute "AXValue" of (value of attribute "AXFocusedUIElement")
          if fe is not missing value then set end of acc to (fe as text)
        end tell
      end tell
    end try
  end if

  set AppleScript's text item delimiters to (ASCII character 10)
  return acc as text
end run
APPLESCRIPT
}

raw="$(read_ax || true)"

# --- clean the AX dump -------------------------------------------------------
# A static blocklist of exact UI-chrome lines (Claude Desktop + generic), the
# summary-anchor prefixes that duplicate message bodies, then consecutive-dedupe.
clean() {
  awk '
    BEGIN {
      # Exact-match chrome lines to drop.
      split("Skip to content|Sidebar|Resize sidebar|Collapse sidebar|Search|Mode|Chat|Cowork|Code|New chat|Projects|Artifacts|Customize|Recents|View all|Get apps and extensions|Primary pane|Share chat|Message actions|Copy|Retry|Edit|Read aloud|Give positive feedback|Give negative feedback|Searched the web|Write a message…|Write a message...|High|Press and hold to record|Marton|Max|Marton Sari", arr, "|")
      for (i in arr) block[arr[i]] = 1
    }
    {
      line = $0
      # Trim surrounding whitespace for matching.
      t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
      if (t == "") next
      if (t in block) next
      # Drop summary-anchor lines that duplicate the body text that follows.
      if (t ~ /^Claude responded:/) next
      if (t ~ /^You said:/) next
      if (t ~ /^More options for /) next
      if (t ~ /^Model:/) next
      # Drop bare clock timestamps like "2:35 PM".
      if (t ~ /^[0-9]{1,2}:[0-9]{2}( ?[AP]M)?$/) next
      # Drop a bare Claude model-name chrome line (e.g. "Opus 4.8", "Sonnet 4.6 High").
      if (t ~ /^(Opus|Sonnet|Haiku)[ ]?[0-9.]*([ ](High|Low|Medium))?$/) next
      # Consecutive dedupe (kills the label-then-value and verbatim doublings).
      if (t == prev) next
      prev = t
      print t
    }
  '
}

cleaned="$(printf '%s' "$raw" | clean)"

# Trim leading/trailing whitespace overall.
cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"
cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"

# Byte-cap, keeping the TAIL (nearest the cursor / most recent is most relevant).
printf '%s' "$cleaned" | tail -c "$MAXBYTES"
