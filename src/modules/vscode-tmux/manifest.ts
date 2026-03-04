import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'vscode-tmux',
  name: 'VS Code Tmux',
  description: 'VS Code terminal profile command: independent or linked tmux sessions per tab, with --claude flag support.',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
  ],
  hooks: [],
  assets: [
    {
      source: 'vscode-tmux.sh.tpl',
      target: 'scripts',
      filename: 'vscode-tmux.sh',
      executable: true,
    },
  ],
};
