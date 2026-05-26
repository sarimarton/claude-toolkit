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
      source: 'claude-toolkit-update.sh.tpl',
      target: 'scripts',
      filename: 'claude-toolkit-update.sh',
      executable: true,
    },
    {
      source: 'swiftbar-install.sh.tpl',
      target: 'scripts',
      filename: 'swiftbar-install.sh',
      executable: true,
    },
    {
      source: 'swiftbar-watchdog.sh.tpl',
      target: 'scripts',
      filename: 'swiftbar-watchdog.sh',
      executable: true,
    },
    {
      source: 'com.sarim.swiftbar-claude-watchdog.plist.tpl',
      target: 'launchagents',
      filename: 'com.sarim.swiftbar-claude-watchdog.plist',
    },
  ],
  // Install SwiftBar.app (via brew cask) if missing, point it at the plugin dir, and launch it.
  // Also registers the claude watchdog LaunchAgent.
  postInstall: '{{scripts_dir}}/swiftbar-install.sh',
};
