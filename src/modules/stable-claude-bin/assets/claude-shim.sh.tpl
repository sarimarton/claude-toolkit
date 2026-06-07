#!/usr/bin/env bash
# claude (shim) — force every `claude` invocation through the TCC-stable launcher.
#
# WHY THIS EXISTS
#   The claude-stable launcher only fixes TCC for invocations that actually go
#   through it (the dual-config claude() function, the auto-dev workflow). But a
#   *bare* `claude` typed in a shell that hasn't sourced claude-fn.sh — or any
#   non-interactive context (`zsh -ic claude`, a cron job, a direct PATH lookup)
#   — resolves `claude` straight to ~/.local/bin/claude → ~/.local/share/claude/
#   versions/<X>. That path changes on every update, so TCC sees a brand-new
#   client and re-prompts for Documents/Desktop/Downloads/Full Disk Access.
#
#   Crucially the background daemon is a per-user singleton with first-spawner-
#   wins semantics: a single direct ~/.local/bin/claude launch pins the daemon
#   to a versions/<X> path for the whole session, and every later launcher-routed
#   session then attaches to that same un-granted daemon. So one bare `claude`
#   anywhere can re-open the prompt flood even when everything else is correct.
#
# HOW THIS FIXES IT
#   This shim lives in {{bin_dir}} (a directory placed AHEAD of ~/.local/bin
#   on PATH) and named `claude`, so it intercepts every PATH-level
#   `claude` and execs the stable launcher instead. Because it is NOT inside
#   Claude's install dir, Claude's self-update — which only rewrites the absolute
#   ~/.local/bin/claude symlink, never a PATH-resolved `claude` — leaves it
#   untouched. The launcher then resolves the current real binary and runs the
#   fixed-path copy, so the daemon and all child spawns share one TCC identity.
#
#   To activate, prepend this dir to PATH from your shell rc (the toolkit never
#   edits your rc itself):
#       export PATH="{{bin_dir}}:$PATH"
set -euo pipefail

STABLE_LAUNCHER="{{scripts_dir}}/claude-stable"

# Prefer the stable launcher; fall back to the real install symlink so a missing
# or not-yet-installed launcher never blocks a launch (correctness over TCC).
# The fallback MUST be the install path, never a PATH-resolved `claude` — this
# script IS the PATH `claude`, so `exec claude` would re-exec itself forever.
if [[ -x "$STABLE_LAUNCHER" ]]; then
  exec "$STABLE_LAUNCHER" "$@"
fi
exec "{{home}}/.local/bin/claude" "$@"
