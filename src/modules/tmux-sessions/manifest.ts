import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'tmux-sessions',
  name: 'Tmux Sessions',
  description: 'AI session aggregator: scans tmux panes, summarizes via Claude. Provides the "ts" command and /tmux slash command.',
  platform: 'any',
  dependencies: [
    { module: 'topic-markers', type: 'hard' },
  ],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI', required: true },
  ],
  hooks: [],
  assets: [
    {
      source: 'tmux-scan.sh.tpl',
      target: 'scripts',
      filename: 'tmux-scan.sh',
      executable: true,
    },
    {
      source: 'tmux-fast.sh.tpl',
      target: 'scripts',
      filename: 'tmux-fast.sh',
      executable: true,
    },
    {
      source: 'tmux-sessions.sh.tpl',
      target: 'scripts',
      filename: 'tmux-sessions.sh',
      executable: true,
    },
  ],
  commands: [
    {
      source: 'tmux.md.tpl',
      target: 'commands',
      filename: 'tmux.md',
      executable: false,
    },
  ],
};
