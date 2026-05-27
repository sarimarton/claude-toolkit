# Claude Toolkit

- Changes only take effect after push — the menubar "⬆ Update available" item handles reinstall.
- **NEVER push to consumer/downstream repos as a shortcut.** This toolkit generates files into consumer repos (e.g. `.github/workflows/auto-dev.yml`). When fixing a bug observed in a consumer repo, the ONLY allowed flow is: fix the template here → commit → push → user runs the menubar Update + per-repo "Update auto-dev" cycle to propagate. NEVER bypass this by editing or `gh api`-patching the downstream repo directly, even if the toolkit update cycle feels slow or the downstream change is "obviously the same." Shortcutting the user's workflow corrupts their source-of-truth, conflicts with their later push, and makes RCA impossible.
