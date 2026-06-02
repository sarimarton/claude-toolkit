#!/usr/bin/env bash
# claude-stable — run Claude Code from a TCC-stable path.
#
# WHY THIS EXISTS
#   macOS TCC keys file-access grants (Documents/Desktop/Downloads/Full Disk
#   Access) for a *bare CLI binary* on its absolute path. Claude Code installs
#   every version at ~/.local/share/claude/versions/<X> and re-points the
#   ~/.local/bin/claude symlink, so each silent auto-update is a brand-NEW path
#   in TCC's eyes → every grant must be re-approved → a cascade of permission
#   prompts after each update. In headless contexts (auto-dev runner) Claude is
#   its own "responsible process", so it is tracked per-version individually.
#
# HOW THIS FIXES IT
#   We maintain a byte-identical copy of the current Claude binary at a FIXED
#   path and exec() it. Because `cp` preserves the embedded code signature, the
#   copy keeps Claude's Developer ID (Anthropic, Team Q6L2SF6YDW). TCC stores a
#   code *requirement* (csreq) per grant, not a cdhash — so when a new version
#   is copied over the same path, TCC re-validates it against the stored
#   requirement and stays silent. Grant the stable path ONCE; never re-prompt.
#
#   The intermediate bash process is replaced via exec(), so the TCC client is
#   the fixed-path Mach-O, not this script.
set -euo pipefail

REAL_LINK="{{claude}}"                    # version symlink: ~/.local/bin/claude
STABLE="{{home}}/.local/libexec/claude"   # FIXED path — grant THIS in Full Disk Access
VERFILE="$STABLE.ver"

# Resolve the current real binary behind the version symlink. macOS `readlink`
# has no reliable -f, so resolve one level and absolutize a relative target.
real="$(readlink "$REAL_LINK" 2>/dev/null || echo "$REAL_LINK")"
case "$real" in
  /*) ;;                                   # already absolute
  *)  real="$(dirname "$REAL_LINK")/$real" ;;
esac

# If we can't find a usable real binary, fall back to the symlink directly
# (correctness over TCC-stability — never block a launch).
if [[ ! -x "$real" ]]; then
  exec "$REAL_LINK" "$@"
fi

ver="$(basename "$real")"

# Refresh the stable copy only when the version changed (cheap marker check).
if [[ ! -f "$STABLE" || "$(cat "$VERFILE" 2>/dev/null || true)" != "$ver" ]]; then
  mkdir -p "$(dirname "$STABLE")"
  tmp="$STABLE.tmp.$$"
  cp -f "$real" "$tmp"                     # byte-for-byte → preserves code signature
  chmod +x "$tmp"
  mv -f "$tmp" "$STABLE"                   # atomic rename: safe even while old copy runs
  printf '%s' "$ver" > "$VERFILE"
fi

exec "$STABLE" "$@"
