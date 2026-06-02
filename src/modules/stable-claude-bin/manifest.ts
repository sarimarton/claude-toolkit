import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'stable-claude-bin',
  name: 'Stable Claude Binary',
  description:
    'Runs Claude Code from a fixed path so macOS file-access (TCC) grants survive silent version updates. ' +
    'Maintains a signature-preserving copy at ~/.local/libexec/claude and execs it.',
  longDescription:
    'macOS TCC keys file-access grants (Documents/Desktop/Downloads/Full Disk Access) for bare CLI ' +
    'binaries on their absolute path. Claude installs each version at ~/.local/share/claude/versions/<X> ' +
    'and re-points ~/.local/bin/claude, so every silent auto-update is a new path → all grants must be ' +
    're-approved, flooding you with permission prompts (worst in the headless auto-dev runner).\n\n' +
    'This module installs a claude-stable launcher that keeps a byte-identical copy of the current binary ' +
    'at a FIXED path (~/.local/libexec/claude) and execs it. Because cp preserves the embedded Anthropic ' +
    'Developer ID signature, TCC re-validates new versions against the same stored requirement and stays ' +
    'silent. Grant Full Disk Access to the fixed path ONCE (run claude-stable-setup.sh), never re-prompt.\n\n' +
    'Consumers: the dual-config claude() function and the auto-dev workflow route through claude-stable, ' +
    'falling back to the version symlink if this module is not installed.',
  platform: 'darwin',
  dependencies: [],
  externals: [
    {
      binary: 'claude',
      description: 'Claude Code CLI (version-symlinked binary to mirror)',
      required: true,
    },
    {
      binary: 'codesign',
      description: 'Verifies the stable copy keeps a valid Developer ID signature',
      required: false,
      checkCommand: 'codesign -v "$HOME/.local/libexec/claude" 2>/dev/null',
      fixHint:
        'Run ~/.config/claude-toolkit/scripts/claude-stable-setup.sh and add ~/.local/libexec/claude to Full Disk Access',
    },
  ],
  hooks: [],
  assets: [
    {
      source: 'claude-stable.sh.tpl',
      target: 'scripts',
      filename: 'claude-stable',
      executable: true,
    },
    {
      source: 'claude-stable-setup.sh.tpl',
      target: 'scripts',
      filename: 'claude-stable-setup.sh',
      executable: true,
    },
  ],
  postInstall:
    '{{scripts_dir}}/claude-stable --version >/dev/null 2>&1 || true; ' +
    'echo "stable-claude-bin installed. Run {{scripts_dir}}/claude-stable-setup.sh once, ' +
    'then add ~/.local/libexec/claude to Full Disk Access."',
};
