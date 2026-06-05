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
      source: 'claude-resume.sh.tpl',
      target: 'scripts',
      filename: 'claude-resume.sh',
      executable: true,
    },
    {
      source: 'claude-auto-resume.sh.tpl',
      target: 'scripts',
      filename: 'claude-auto-resume.sh',
      executable: true,
    },
    {
      source: 'claude-resume-cleanup.sh.tpl',
      target: 'scripts',
      filename: 'claude-resume-cleanup.sh',
      executable: true,
    },
    {
      source: 'claude-toolkit-update.sh.tpl',
      target: 'scripts',
      filename: 'claude-toolkit-update.sh',
      executable: true,
    },
    {
      source: 'claude-toolkit-update-worker.sh.tpl',
      target: 'scripts',
      filename: 'claude-toolkit-update-worker.sh',
      executable: true,
    },
    {
      source: 'edit-config.sh.tpl',
      target: 'scripts',
      filename: 'edit-config.sh',
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
  // tmux directives for reboot resume (see claude-auto-resume.sh / claude-resume.sh).
  // Written to a generated drop-in (~/.config/tmux/tmux.conf.d/claude-toolkit-menubar.conf),
  // NOT into the user's tmux.conf — so the user doesn't have to know tmux must be touched,
  // and the version-controlled config stays clean. Requires the user's tmux.conf to source
  // the drop-in glob once (install.sh adds it).
  tmuxConf: {
    lines: [
      '# Auto-resume dead Claude panes when an iTerm2 (-CC) client attaches. After a',
      '# reboot, continuum restores the "✻ topic" windows as plain shells (the claude',
      '# process is gone — see the @resurrect-processes override below). On attach,',
      '# resume each dead pane in place with the exact recorded UUID. Control-mode only,',
      "# so it fires for iTerm's -CC attach, not every client. The script self-guards",
      '# (skips already-alive panes and topics with no surviving .jsonl) → re-attach no-op.',
      'set-hook -ga client-attached \'if -F "#{client_control_mode}" "run-shell \\"{{scripts_dir}}/claude-auto-resume.sh #{session_name}\\""\'',
    ],
    overrides: [
      // Drop "~claude" from resurrect's process-restore list: re-running the saved
      // `claude …` command line opens a FRESH, empty session (the conversation is a
      // JSONL transcript keyed by session-id, absent from the bare command line). We
      // want the topic panes restored as plain shells so the proper resume path (menu
      // ○ or the auto-resume hook above, both with the recorded UUID) takes over.
      // Last-write-wins + drop-in sourced last → this shadows the main config's value.
      "set -g @resurrect-processes '\"~node\"'",
    ],
  },
  // Install SwiftBar.app (via brew cask) if missing, point it at the plugin dir, and launch it.
  // Also registers the claude watchdog LaunchAgent.
  postInstall: '{{scripts_dir}}/swiftbar-install.sh',
};
