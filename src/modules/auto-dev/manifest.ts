import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'auto-dev',
  name: 'Auto-dev',
  description: 'GitHub Actions-based autonomous issue→PR→implementation pipeline. Installs a self-hosted runner into target repos and drives development cycles using Claude, respecting plan tier rate limits.',
  longDescription: `Autonomous issue→PR→implementation pipeline using GitHub Actions and Claude Code.

Issues labeled 'ai' enter a hierarchical label-based state machine, advancing one step per workflow run:

  new → evaluate (clarify / ready / blocked / epic)
  ready → plan todos → open draft PR
  in-progress → implement one task → commit → push
  done → mark PR ready for review

Labels used: ai, ai:ready, ai:in-progress, ai:done, ai:blocked, ai:clarifying, ai:epic.
Model overrides: add 'opus' or 'haiku' label to an issue to change the model for that cycle.

Rate limiting: each run checks usage-monitor output first and skips if Claude usage exceeds a configurable threshold (default: 50% of plan bucket). Autonomy can be set to 'low' to require human approval before PRs are created.

PM agent (runs every 6h): reviews backlog health, responds to owner comments, creates sub-issues for epics, and optionally writes README.md for new repos.

Menubar: adds a SwiftBar section showing managed repos (tagged with GitHub topic 'auto-dev'), runner status (tmux session), and per-repo cycle history.

Setup: SwiftBar menu → "Install Auto-dev to repo…", or run:
  auto-dev-runner-setup.sh <owner/repo>`,
  platform: 'darwin',
  dependencies: [
    { module: 'menubar', type: 'hard' },
    { module: 'usage-monitor', type: 'hard' },
  ],
  externals: [
    {
      binary: 'gh',
      description: 'GitHub CLI (auth + project scope)',
      required: true,
      installHint: 'brew install gh && gh auth login',
      // Project board ensure (auto-dev-project-ensure.sh) needs the `project` scope.
      checkCommand: `gh auth status 2>&1 | grep -i 'token scopes' | grep -q project`,
      fixHint: 'gh auth refresh -s project,read:project',
    },
    { binary: 'jq', description: 'JSON processor', required: true, installHint: 'brew install jq' },
    { binary: 'yq', description: 'YAML processor (reads config.yaml at runtime)', required: true, installHint: 'brew install yq' },
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI', required: true },
  ],
  hooks: [],
  assets: [
    {
      source: 'runner-setup.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-runner-setup.sh',
      executable: true,
    },
    {
      source: 'runner-control.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-runner-control.sh',
      executable: true,
    },
    {
      source: 'auto-dev-section.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-section.sh',
      executable: true,
    },
    {
      source: 'auto-dev-install.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-install.sh',
      executable: true,
    },
    {
      source: 'auto-dev-reinstall.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-reinstall.sh',
      executable: true,
    },
    {
      source: 'auto-dev-workflow-push.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-workflow-push.sh',
      executable: true,
    },
    {
      source: 'auto-dev-reregister.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-reregister.sh',
      executable: true,
    },
    {
      source: 'auto-dev-gh-fix-scope.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-gh-fix-scope.sh',
      executable: true,
    },
    {
      source: 'auto-dev-attach.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-attach.sh',
      executable: true,
    },
    {
      source: 'auto-dev-cycle.yml.tpl',
      target: 'scripts',
      filename: 'auto-dev-cycle.yml',
      executable: false,
    },
    {
      source: 'auto-dev-label.yml.tpl',
      target: 'scripts',
      filename: 'auto-dev-label.yml',
      executable: false,
    },
    {
      source: 'auto-dev-config.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-config.sh',
      executable: true,
    },
    {
      source: 'auto-dev-pm.yml.tpl',
      target: 'scripts',
      filename: 'auto-dev-pm.yml',
      executable: false,
    },
    {
      source: 'auto-dev-pm-run.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-pm-run.sh',
      executable: true,
    },
    {
      source: 'auto-dev-rebase.yml.tpl',
      target: 'scripts',
      filename: 'auto-dev-rebase.yml',
      executable: false,
    },
    {
      source: 'auto-dev-project-ensure.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-project-ensure.sh',
      executable: true,
    },
    {
      source: 'auto-dev-project-sync.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-project-sync.sh',
      executable: true,
    },
  ],
  // The GitHub-tracking-sync policy that governs how interactive Claude should keep
  // board/issue/PR in sync inside auto-dev repos. Lives with the module (source of
  // truth) and is injected into the user-level CLAUDE.md via the @import drop-in.
  claudeMdBlocks: [
    { source: 'github-sync-policy.md.tpl', sectionId: 'github-sync' },
  ],
  postInstall:
    'echo "auto-dev module installed. Run auto-dev-runner-setup.sh <owner/repo> to install into a target repository." && ' +
    'echo "GitHub-sync policy written to {{claude_md_dir}}/auto-dev-github-sync.md and auto-imported into ~/.claude/CLAUDE.md (if it exists)."',
};
