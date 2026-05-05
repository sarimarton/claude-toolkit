import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'tmux-prompt-marks',
  name: 'Tmux Prompt Marks',
  description: 'Visual + structural prompt anchors in tmux scrollback: numbered separator with timestamp + cwd (chapter markers), OSC 133 prompt-mark sequences for tmux next-prompt/previous-prompt jump actions, and an auto-bookmark stack that snapshots the buffer position before every command for browser-style "jump to last command" navigation.',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer (>=3.4 for next-prompt/previous-prompt actions)', required: true, installHint: 'brew install tmux' },
    { binary: 'zsh', description: 'Shell with precmd/preexec hooks (the marks integrate via add-zsh-hook)', required: true },
  ],
  hooks: [],
  assets: [
    {
      source: 'prompt-marks.zsh.tpl',
      target: 'scripts',
      filename: 'prompt-marks.zsh',
      executable: false,
    },
    {
      source: 'prompt-bookmark.sh.tpl',
      target: 'scripts',
      filename: 'prompt-bookmark.sh',
      executable: true,
    },
  ],
};
