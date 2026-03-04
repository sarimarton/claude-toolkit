import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'sounds',
  name: 'Sounds',
  description: 'Plays sound effects on tool use and stop events (macOS afplay). Suppressed in pipe mode.',
  platform: 'darwin',
  dependencies: [],
  externals: [],
  hooks: [
    {
      event: 'PreToolUse',
      matcher: '.*',
      command: '{{hooks_dir}}/play-sound.sh /System/Library/Sounds/Frog.aiff',
    },
    {
      event: 'Stop',
      matcher: '',
      command: '{{hooks_dir}}/play-sound.sh /System/Library/Sounds/Hero.aiff',
    },
  ],
  assets: [
    {
      source: 'play-sound.sh.tpl',
      target: 'hooks',
      filename: 'play-sound.sh',
      executable: true,
    },
  ],
};
