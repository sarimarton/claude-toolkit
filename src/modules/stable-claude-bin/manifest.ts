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
    'falling back to the version symlink if this module is not installed.\n\n' +
    'IMPORTANT — the launcher only fixes TCC for invocations that actually go through it. A bare `claude` ' +
    'in a shell that has not sourced claude-fn.sh, or any non-interactive context, resolves straight to ' +
    '~/.local/bin/claude → versions/<X> and re-prompts on every update. The background daemon makes this ' +
    'worse: it is a per-user singleton with first-spawner-wins semantics, so ONE direct ~/.local/bin/claude ' +
    'launch pins the daemon to a versions/<X> path for the whole session, and later launcher-routed sessions ' +
    'attach to that same un-granted daemon. To close this, the module also installs a `claude` PATH shim ' +
    '(claude-shim.sh) in ~/.config/claude-toolkit/bin; prepend that dir ahead of ~/.local/bin on PATH so ' +
    'EVERY claude launch routes through the launcher. The shim is safe across Claude self-updates, which only ' +
    'rewrite the absolute ~/.local/bin/claude symlink and never a PATH-resolved `claude`.',
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
    {
      // PATH shim named `claude` in a dir prepended ahead of ~/.local/bin, so
      // even bare `claude` / `zsh -ic claude` / direct manual launches route
      // through the stable launcher (not just the dual-config claude() function).
      source: 'claude-shim.sh.tpl',
      target: 'bin',
      filename: 'claude',
      executable: true,
    },
  ],
  postInstall:
    '{{scripts_dir}}/claude-stable --version >/dev/null 2>&1 || true; ' +
    'echo "stable-claude-bin installed. Run {{scripts_dir}}/claude-stable-setup.sh once, ' +
    'then add ~/.local/libexec/claude to Full Disk Access. ' +
    'To route ALL claude launches (bare/manual/non-interactive) through it, ' +
    'prepend the shim dir to PATH in your shell rc: ' +
    'export PATH=\\"{{bin_dir}}:\\$PATH\\""',
};
