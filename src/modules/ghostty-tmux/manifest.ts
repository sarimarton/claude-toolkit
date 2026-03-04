import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'ghostty-tmux',
  name: 'Ghostty Tmux',
  description: 'Ghostty tab command: handles attach signals, claude signals, session restore, and cleanup on close.',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
  ],
  hooks: [],
  assets: [
    {
      source: 'ghostty-tmux.sh.tpl',
      target: 'scripts',
      filename: 'ghostty-tmux.sh',
      executable: true,
    },
  ],
};
