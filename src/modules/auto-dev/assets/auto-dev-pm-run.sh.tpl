#!/usr/bin/env bash
# auto-dev-pm-run.sh — Trigger the PM agent workflow via workflow_dispatch
#
# Usage: auto-dev-pm-run.sh <owner/repo> [user_message]

set -euo pipefail

export PATH="{{home}}/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

REPO="${1:-}"

if [[ -z "$REPO" ]]; then
  echo "Usage: auto-dev-pm-run.sh <owner/repo> [user_message]"
  exit 1
fi

# Optional: prompt for a message to the PM agent
USER_MESSAGE="${2:-}"
if [[ -z "$USER_MESSAGE" ]]; then
  USER_MESSAGE=$(osascript -e 'text returned of (display dialog "Optional message to the PM agent (leave blank for autonomous run):" default answer "" with title "Auto-dev PM" buttons {"Cancel", "Run"} default button "Run")' 2>/dev/null || true)
  [[ "$USER_MESSAGE" == "" ]] && true  # empty is fine — autonomous run
fi

if [[ -n "$USER_MESSAGE" ]]; then
  gh workflow run auto-dev-pm.yml \
    --repo "$REPO" \
    --field "user_message=$USER_MESSAGE"
else
  gh workflow run auto-dev-pm.yml \
    --repo "$REPO"
fi

osascript -e "display notification \"PM agent triggered for $REPO\" with title \"Auto-dev PM\" subtitle \"Check GitHub Actions for progress\"" 2>/dev/null || true
echo "PM agent workflow triggered for $REPO"
