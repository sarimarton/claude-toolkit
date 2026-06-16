import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'auto-dev-installer',
  name: 'Auto-dev Installer',
  description:
    'Install Auto-dev into the CURRENT GitHub repo straight from a Claude prompt — exposes both the /install-autodev slash command and an install-autodev skill. Both are thin wrappers over the canonical auto-dev-runner-setup.sh; no install logic is duplicated.',
  longDescription:
    'The Auto-dev module already ships a self-contained CLI entrypoint, auto-dev-runner-setup.sh <owner/repo>, which (given the arg, i.e. no AppleScript picker) performs the full install: registration token → runner binary → runner config → the four auto-dev-*.yml workflows committed into the repo → auto-dev GitHub topic → project board + labels. The SwiftBar "Install Auto-dev to repo…" button is itself just a picker in front of this script. This module surfaces the same capability from a Claude prompt in two shapes that target the repo Claude is currently standing in (resolved via `gh repo view`): a /install-autodev slash command (explicit) and an install-autodev SKILL.md (autonomous — triggers when the user asks to "install auto-dev here"). Both call the one canonical script, honoring the toolkit contract (never hand-patch a downstream repo).',
  platform: 'darwin',
  dependencies: [
    // The install logic and the auto-dev-runner-setup.sh entrypoint live in the
    // auto-dev module; we are a pure wrapper over it. Hard dep guarantees the
    // script is present in scriptsDir before our command/skill can call it.
    { module: 'auto-dev', type: 'hard' },
  ],
  externals: [
    { binary: 'gh', description: 'GitHub CLI — resolves the current repo and drives the install (needs the `project` scope for the board)', required: true, installHint: 'brew install gh' },
  ],
  hooks: [],
  assets: [],
  // Both surfaces ship via the `commands` install pass, which honors each entry's
  // own `target` (getTargetDir). No new manifest field or install-loop branch is
  // needed — the only new machinery is the 'skills' AssetTarget itself.
  commands: [
    // 'commands' renders into ~/.config/claude-toolkit/commands (Claude Code does
    // NOT read there) — postInstall symlinks it into ~/.claude/commands.
    { source: 'install-autodev.md.tpl', target: 'commands', filename: 'install-autodev.md', executable: false },
    // 'skills' renders straight into ~/.claude/skills/install-autodev/SKILL.md,
    // where Claude Code discovers skills directly (no symlink hop). installTemplate
    // mkdir -p's the intermediate dir from the filename.
    { source: 'SKILL.md.tpl', target: 'skills', filename: 'install-autodev/SKILL.md', executable: false },
  ],
  // Land the slash command where Claude Code loads user commands. The skill
  // already renders straight into ~/.claude/skills via the 'skills' target.
  postInstall:
    'mkdir -p "{{claude_dir}}/commands" && ln -sf "{{commands_dir}}/install-autodev.md" "{{claude_dir}}/commands/install-autodev.md"',
  postUninstall:
    'rm -f "{{claude_dir}}/commands/install-autodev.md" && rm -rf "{{skills_dir}}/install-autodev"',
};
