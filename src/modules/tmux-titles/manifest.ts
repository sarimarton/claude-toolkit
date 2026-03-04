import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'tmux-titles',
  name: 'Tmux Titles',
  description: 'Stop hook: extracts $topic marker from pane buffer and sets tmux window name + VS Code terminal-topic JSON',
  platform: 'any',
  dependencies: [
    { module: 'topic-markers', type: 'hard' },
  ],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
  ],
  hooks: [
    {
      event: 'Stop',
      matcher: '',
      command: '{{hooks_dir}}/set-tmux-title.sh',
    },
  ],
  assets: [
    {
      source: 'set-tmux-title.sh.tpl',
      target: 'hooks',
      filename: 'set-tmux-title.sh',
      executable: true,
    },
  ],
};
