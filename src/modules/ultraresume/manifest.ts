import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'ultraresume',
  name: 'Ultra Resume',
  description:
    'Resume the PRIOR Claude session shown in a pane\'s scrollback by its $topic marker. Provides the /ultraresume slash command (self-injects /resume into the pane) and the claude-ultraresume CLI.',
  longDescription:
    'From inside a live Claude pane, /ultraresume reads the scrollback, finds the previous session by the near-unique "$topic" marker it left behind, resolves that session\'s transcript UUID under ~/.claude/projects (scoped to the pane\'s cwd, excluding the current session via newest-mtime self-detection), and self-injects "/resume <uuid>" + Enter into the pane — the same tmux send-keys primitive the reboot-recovery menu uses. The shared lookup lib (ur_marker_topic / ur_scrollback_topic / ur_resolve_uuid) is unit-tested. claude-ultraresume.sh exposes the same lookup as an external CLI that execs `claude --resume` from the session\'s own cwd, either from scrollback (in tmux) or from explicit topic words.',
  platform: 'darwin',
  dependencies: [
    // topic-markers writes the "$topic" markers this feature matches on, and ships
    // claude-stable (the CLAUDE_BIN the external entrypoint prefers).
    { module: 'topic-markers', type: 'hard' },
  ],
  externals: [
    { binary: 'tmux', description: 'capture-pane (scrollback) + send-keys (self-inject)', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI (external --resume path)', required: true },
  ],
  hooks: [],
  assets: [
    // Shared pure-logic lib (sourced, not executable on its own) — the tested core.
    { source: 'ultraresume-lib.sh.tpl',     target: 'scripts', filename: 'ultraresume-lib.sh',     executable: false },
    // In-pane entrypoint invoked by the /ultraresume slash command.
    { source: 'ultraresume-inject.sh.tpl',  target: 'scripts', filename: 'ultraresume-inject.sh',  executable: true },
    // External CLI (symlinked onto PATH as `claude-ultraresume`, see postInstall).
    { source: 'claude-ultraresume.sh.tpl',  target: 'scripts', filename: 'claude-ultraresume.sh',  executable: true },
  ],
  commands: [
    // The 'commands' target renders into ~/.config/claude-toolkit/commands, which
    // Claude Code does NOT read — postInstall symlinks it into ~/.claude/commands.
    { source: 'ultraresume.md.tpl', target: 'commands', filename: 'ultraresume.md', executable: false },
  ],
  cli: [
    {
      name: 'claude-ultraresume',
      description: 'Resume the prior session shown in this pane\'s scrollback, by its $topic marker',
      script: 'claude-ultraresume.sh',
      usage: 'claude-ultraresume [-n] [topic words…]',
    },
  ],
  // Land the slash command where Claude Code loads user commands, and expose the
  // external CLI on PATH (~/.local/bin is what setup.sh adds).
  postInstall:
    'mkdir -p "{{claude_dir}}/commands" && ln -sf "{{commands_dir}}/ultraresume.md" "{{claude_dir}}/commands/ultraresume.md" && ' +
    'mkdir -p "$HOME/.local/bin" && ln -sf "{{scripts_dir}}/claude-ultraresume.sh" "$HOME/.local/bin/claude-ultraresume"',
  postUninstall:
    'rm -f "{{claude_dir}}/commands/ultraresume.md" "$HOME/.local/bin/claude-ultraresume"',
};
