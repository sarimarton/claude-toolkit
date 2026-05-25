import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'auto-dev',
  name: 'Auto-dev',
  description: 'GitHub Actions-based iterative development manager. Installs a self-hosted runner and workflow into target repos, then drives issue→PR→implementation cycles using Claude — respecting plan tier rate limits. Adds a SwiftBar section to the Claude menu for runner control and cycle history.',
  platform: 'darwin',
  dependencies: [
    { module: 'menubar', type: 'hard' },
    { module: 'usage-monitor', type: 'hard' },
  ],
  externals: [
    { binary: 'gh', description: 'GitHub CLI', required: true, installHint: 'brew install gh' },
    { binary: 'jq', description: 'JSON processor', required: true, installHint: 'brew install jq' },
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI', required: true },
    { binary: 'gum', description: 'Charm gum (TUI tool)', required: true, installHint: 'brew install gum' },
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
      source: 'auto-dev-attach.sh.tpl',
      target: 'scripts',
      filename: 'auto-dev-attach.sh',
      executable: true,
    },
    {
      source: 'auto-dev.yml.tpl',
      target: 'scripts',
      filename: 'auto-dev.yml',
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
  ],
  postInstall: 'echo "auto-dev module installed. Run auto-dev-runner-setup.sh <owner/repo> to install into a target repository."',
};
