import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'notifications',
  name: 'Notifications',
  description: 'Desktop notifications via terminal-notifier with Hammerspoon focus-on-click integration.',
  platform: 'darwin',
  dependencies: [],
  externals: [
    { binary: 'terminal-notifier', description: 'macOS notification tool', required: true, installHint: 'brew install terminal-notifier' },
    { binary: 'jq', description: 'JSON processor', required: true, installHint: 'brew install jq' },
  ],
  hooks: [
    {
      event: 'Notification',
      matcher: '',
      command: '{{hooks_dir}}/notification.sh',
    },
  ],
  assets: [
    {
      source: 'notification.sh.tpl',
      target: 'hooks',
      filename: 'notification.sh',
      executable: true,
    },
  ],
};
