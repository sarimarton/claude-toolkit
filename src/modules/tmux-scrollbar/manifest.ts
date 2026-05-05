import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'tmux-scrollbar',
  name: 'Tmux Scrollbar',
  description: 'Sub-cell precision character scrollbar for tmux status-right (8x resolution via Unicode block glyphs + REVERSE trick), plus a click handler that turns a click on the bar into a goto-position jump in copy-mode.',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
  ],
  hooks: [],
  assets: [
    {
      source: 'scrollbar.sh.tpl',
      target: 'scripts',
      filename: 'scrollbar.sh',
      executable: true,
    },
    {
      source: 'scrollbar-click.sh.tpl',
      target: 'scripts',
      filename: 'scrollbar-click.sh',
      executable: true,
    },
  ],
};
