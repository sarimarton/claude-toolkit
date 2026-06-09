#!/usr/bin/env sh
# setup-guard.sh — pure decision logic for setup.sh, kept separate so it can be
# unit-tested without running the full installer (npm/git). No side effects.

# needs_deploy_target_confirmation <script_dir> <canonical_deploy_dir> <explicit_dir> <assume_yes>
#
# Returns 0 (true) when ./setup.sh is about to make a NON-canonical directory the
# deploy target (install dir) without the user having opted in — i.e. the "dev
# clone becomes deploy target" trap. Returns 1 (false) when it is safe to proceed
# silently: the canonical deploy location, an explicit CLAUDE_TOOLKIT_DIR, or --yes.
needs_deploy_target_confirmation() {
  _script_dir="$1"; _canonical="$2"; _explicit="$3"; _assume_yes="$4"

  # Explicit target or --yes → the user has chosen; never second-guess.
  [ -n "$_explicit" ] && return 1
  [ "$_assume_yes" = "true" ] && return 1

  # Canonical deploy location → the intended fresh-install path, no prompt.
  [ "$_script_dir" = "$_canonical" ] && return 1

  # Anything else (a dev clone, an arbitrary checkout) → warrant a confirmation.
  return 0
}
