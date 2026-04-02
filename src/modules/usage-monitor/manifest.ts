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
    { binary: 'yq', description: 'YAML processor (for multi-account config)', required: false, installHint: 'brew install yq' },
  ],
  hooks: [],
  assets: [
    {
      source: 'claude-usage-poll.sh.tpl',
      target: 'scripts',
      filename: 'claude-usage-poll.sh',
      executable: true,
    },
    {
      source: 'usage-chart.sh.tpl',
      target: 'scripts',
      filename: 'usage-chart.sh',
      executable: true,
    },
  ],
};
