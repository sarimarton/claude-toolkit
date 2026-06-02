#!/usr/bin/env bash
# claude-stable-setup — materialize the TCC-stable Claude binary and guide the
# one-time Full Disk Access grant.
#
# Run this once after installing the stable-claude-bin module. It creates the
# fixed-path copy, reveals it in Finder, and opens the Full Disk Access pane so
# you can add it. Because the path never changes across Claude updates, this is
# a one-time action — future silent updates re-validate against the same grant.
set -euo pipefail

STABLE="{{home}}/.local/libexec/claude"
LAUNCHER="{{scripts_dir}}/claude-stable"

# Materialize / refresh the stable copy (the launcher syncs then runs --version).
"$LAUNCHER" --version >/dev/null 2>&1 || true

if [[ ! -f "$STABLE" ]]; then
  echo "ERROR: could not create the stable copy at:" >&2
  echo "  $STABLE" >&2
  echo "Is Claude Code installed (~/.local/bin/claude)?" >&2
  exit 1
fi

echo "TCC-stable Claude binary ready:"
echo "  $STABLE"
echo
codesign -dv "$STABLE" 2>&1 | grep -E 'Authority=Developer ID|TeamIdentifier' || true
echo
echo "Next: add the path above to Full Disk Access."
echo "It never changes across Claude updates, so you grant it only ONCE —"
echo "every future silent update re-validates against the same grant."
echo

# Reveal in Finder + open the Full Disk Access pane (best-effort).
open -R "$STABLE" 2>/dev/null || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
