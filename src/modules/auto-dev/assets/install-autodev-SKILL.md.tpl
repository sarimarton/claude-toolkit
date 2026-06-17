---
name: install-autodev
description: Install Auto-dev (claude-toolkit's issue→PR pipeline — self-hosted runner + the four auto-dev-*.yml workflows + the auto-dev GitHub topic, project board and ai/ai:ready/ai:epic labels) into a GitHub repository. Use when the user asks to "install auto-dev", "set up auto-dev here", "add auto-dev to this repo", "enable the auto-dev pipeline", or similar — typically from inside the repo they want it in.
user-invocable: true
allowed-tools:
  - Bash({{scripts_dir}}/auto-dev-runner-setup.sh:*)
  - Bash(gh repo view:*)
  - Bash(gh auth status:*)
---

# install-autodev — install Auto-dev into a GitHub repo

Auto-dev is the claude-toolkit pipeline that turns `ai`-labelled issues into PRs via a
self-hosted GitHub Actions runner. This skill installs it into a repository by calling
the one canonical installer script — it does **not** re-implement any install logic, and
it never hand-edits the target repo's workflows (the toolkit script is the contract).

## 1. Resolve the target repo

Default target is **the repo the current session is standing in**:

```
gh repo view --json nameWithOwner -q .nameWithOwner
```

- If the user named a specific `owner/repo`, use that instead.
- If this fails (not in a GitHub repo) and the user gave no repo, ask them for `owner/repo`.

## 2. Confirm, then check it isn't already installed

This deploys CI, commits workflows, and starts a runner — so first **confirm the target
with the user** ("Install Auto-dev into `<owner/repo>`?") and get a yes.

Then check the repo isn't already an Auto-dev repo:

```
gh repo view --json repositoryTopics -q '.repositoryTopics[].name' | grep -qx auto-dev
```

- If it matches (`auto-dev` topic present): Auto-dev is already installed. Say so and stop —
  re-running is idempotent and safe, but only proceed if the user explicitly asks to repair.

## 3. Install

Run the canonical installer, passing `owner/repo` explicitly so it does **not** open a
GUI picker:

```
{{scripts_dir}}/auto-dev-runner-setup.sh "<owner/repo>"
```

This: gets a runner registration token → fetches/configures the runner binary → commits
the four `auto-dev-*.yml` workflows into `.github/workflows/` → adds the `auto-dev` topic →
ensures the project board and `ai` / `ai:ready` / `ai:epic` labels.

## 4. Report

Relay the script's outcome: which workflows were committed, whether the topic/board/labels
were ensured, and how to start/attach the runner. If `gh` lacks the `project` scope the
board step warns — surface it so the user can `gh auth refresh -s project`.
