import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'usage-monitor',
  name: 'Usage Monitor',
  description: 'Polls Claude Code /usage via a dedicated tmux session. Writes JSON to /tmp/claude-usage.json for menubar display.',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI', required: true },
    { binary: 'python3', description: 'Python 3 for parsing', required: true },
  ],
  hooks: [],
  assets: [
    {
      source: 'claude-usage-poll.sh.tpl',
      target: 'scripts',
      filename: 'claude-usage-poll.sh',
      executable: true,
    },
  ],
};
