import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'usage-monitor',
  name: 'Usage Monitor',
  description: 'Polls Claude usage via the OAuth /api/oauth/usage endpoint (fast path), falling back to a dedicated tmux /usage session. Writes JSON to /tmp/claude-usage.json for menubar display.',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'curl', description: 'HTTP client for the OAuth usage endpoint (fast path)', required: true },
    { binary: 'security', description: 'macOS keychain reader for the local OAuth token (fast path; single-account)', required: false },
    { binary: 'tmux', description: 'Terminal multiplexer (fallback /usage scrape)', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI (fallback /usage scrape)', required: true },
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
