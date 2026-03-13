import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'vscode-terminal-topic',
  name: 'VS Code Terminal Topic',
  description: 'VS Code extension: renames terminal tabs from Claude $topic markers, syncs tmux titles, Alt+close kills tmux session.',
  platform: 'darwin',
  dependencies: [
    { module: 'topic-markers', type: 'hard' },
    { module: 'tmux-titles', type: 'hard' },
  ],
  externals: [
    { binary: 'code', description: 'VS Code CLI', required: true, installHint: 'Install VS Code and add "code" to PATH' },
  ],
  hooks: [],
  assets: [],
};
