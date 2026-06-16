---
description: Install Auto-dev (self-hosted runner + the four auto-dev-*.yml workflows + GitHub topic, project board and labels) into the CURRENT GitHub repo
allowed-tools: Bash({{scripts_dir}}/auto-dev-runner-setup.sh:*), Bash(gh repo view:*), Bash(gh auth status:*)
argument-hint: "[owner/repo — defaults to the current repo]"
---

Install **Auto-dev** into a GitHub repository, straight from this prompt.

Auto-dev is the claude-toolkit pipeline that turns `ai`-labelled issues into PRs via
a self-hosted GitHub Actions runner. Installing it deploys the four
`.github/workflows/auto-dev-*.yml` workflows, tags the repo with the `auto-dev`
topic, and ensures the project board + `ai` / `ai:ready` / `ai:epic` labels.

### Target repo

Default target is **the repo this session is standing in**. Resolve it with:

!`gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "(not in a GitHub repo)"`

- If the user passed `$ARGUMENTS`, that is the target `owner/repo` instead.
- If neither resolves (not in a GitHub repo and no arg), stop and ask the user for `owner/repo`.

### Before installing — confirm, then check it isn't already installed

1. **Confirm** the resolved target with the user (one line: "Install Auto-dev into `<owner/repo>`?"). This deploys CI, commits workflows, and starts a runner — get a yes first.
2. Check it isn't already an Auto-dev repo:

!`gh repo view --json repositoryTopics -q '.repositoryTopics[].name' 2>/dev/null | grep -qx auto-dev && echo "ALREADY-INSTALLED" || echo "not-installed"`

   - If `ALREADY-INSTALLED`: tell the user Auto-dev is already on this repo and stop (re-running is safe/idempotent, but only proceed if they explicitly ask to repair/re-run).

### Install

Once confirmed and not already installed, run the canonical installer (this is the
*only* install path — never hand-edit the repo's workflows; the toolkit script is the
contract). Pass the resolved `owner/repo` explicitly so it does NOT open a picker:

!`{{scripts_dir}}/auto-dev-runner-setup.sh "<owner/repo>"`

Relay the script's outcome to the user: which workflows were committed, whether the
`auto-dev` topic/board/labels were ensured, and how to start/attach the runner. If
`gh` lacks the `project` scope the board step may warn — surface that so they can
`gh auth refresh -s project`.
