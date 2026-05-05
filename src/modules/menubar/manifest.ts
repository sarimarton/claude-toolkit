import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'menubar',
  name: 'Menubar',
  description: 'SwiftBar menu bar plugin showing usage %, session list, focus/attach/kill controls, and AI-generated peek tooltips.',
  platform: 'darwin',
  dependencies: [
    { module: 'tmux-sessions', type: 'hard' },
    { module: 'usage-monitor', type: 'hard' },
  ],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI', required: true },
  ],
  hooks: [],
  postInstall: '/bin/launchctl unload {{launch_agents_dir}}/com.claude-toolkit.menubar-visibility.plist 2>/dev/null; /bin/launchctl load {{launch_agents_dir}}/com.claude-toolkit.menubar-visibility.plist',
  postUninstall: '/bin/launchctl unload {{home}}/Library/LaunchAgents/com.claude-toolkit.menubar-visibility.plist 2>/dev/null; killall SwiftBar 2>/dev/null; for i in 1 2 3 4 5; do pgrep -q SwiftBar || break; sleep 0.5; done; open -a SwiftBar 2>/dev/null; true',
  assets: [
    {
      source: 'claude.10s.sh.tpl',
      target: 'swiftbar',
      filename: 'claude.10s.sh',
      executable: true,
    },
    {
      source: 'claude-attach.sh.tpl',
      target: 'scripts',
      filename: 'claude-attach.sh',
      executable: true,
    },
    {
      source: 'claude-focus.sh.tpl',
      target: 'scripts',
      filename: 'claude-focus.sh',
      executable: true,
    },
    {
      source: 'claude-kill.sh.tpl',
      target: 'scripts',
      filename: 'claude-kill.sh',
      executable: true,
    },
    {
      source: 'menubar-visibility-fix.sh.tpl',
      target: 'scripts',
      filename: 'menubar-visibility-fix.sh',
      executable: true,
    },
    {
      source: 'com.claude-toolkit.menubar-visibility.plist.tpl',
      target: 'launchagents',
      filename: 'com.claude-toolkit.menubar-visibility.plist',
      executable: false,
    },
  ],
};
