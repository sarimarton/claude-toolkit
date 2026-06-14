#!/usr/bin/env node
import meow from 'meow';
import React from 'react';
import { render } from 'ink';
import { App } from './tui/App.js';
import fs from 'node:fs';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const cli = meow(`
  Usage
    $ claude-toolkit                   Interactive dashboard
    $ claude-toolkit list              List all modules with status
    $ claude-toolkit install [mod..]   Install modules (auto-resolves deps)
    $ claude-toolkit uninstall         Dashboard (select + u to uninstall)
    $ claude-toolkit uninstall [mod..] Uninstall specific modules
    $ claude-toolkit uninstall all     Uninstall all modules
    $ claude-toolkit status            Per-module health check
    $ claude-toolkit doctor            Full integrity audit
    $ claude-toolkit update            Pull latest from origin, rebuild, reinstall modules
    $ claude-toolkit chart             Open usage chart in browser
    $ claude-toolkit tools             List shell utilities shipped by installed modules
    $ claude-toolkit run <tool> [..]   Run a module shell utility (see 'tools')

  Options
    --help       Show this help
    --version    Show version
    --yes, -y    Skip confirmation prompts

  Module shell utilities (crt, claude-tmux, …) stay available under their own
  names on PATH. 'claude-toolkit tools' lists them in one place; 'run' invokes
  them through the toolkit.
`, {
  importMeta: import.meta,
  flags: {
    yes: {
      type: 'boolean',
      shortFlag: 'y',
      default: false,
    },
  },
});

const [command = 'dashboard', ...args] = cli.input;

if (command === 'update') {
  // Must run before Ink takes over the terminal — stdio: 'inherit' streams
  // git/npm output directly. After rebuild, re-exec the (new) cli to upgrade.
  const installDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
  console.log('Fetching latest changes...');
  // Hard-reset to origin/main rather than `git pull`: the install dir is a pristine
  // mirror (development happens in a separate clone), so there is nothing to merge
  // and a reset can never hit a conflict — essential for unattended/background updates.
  execSync('git fetch origin', { cwd: installDir, stdio: 'inherit' });
  execSync('git reset --hard origin/main', { cwd: installDir, stdio: 'inherit' });
  console.log('Rebuilding...');
  execSync('npm ci', { cwd: installDir, stdio: 'inherit' });
  execSync('npm run build', { cwd: installDir, stdio: 'inherit' });
  console.log('Upgrading installed modules...');
  execSync(`${process.execPath} ${path.join(installDir, 'dist', 'cli.js')} reinstall`, { stdio: 'inherit' });
  // Clear update-check cache so the menu reflects the new version immediately
  try { fs.unlinkSync('/tmp/claude-toolkit-update-check.json'); } catch { /* ok if missing */ }
  process.exit(0);
}

// `tools` / `run` deal with module shell utilities. Both are plain stdout/exec
// flows (no Ink TUI), handled before render() like `update`.
if (command === 'tools' || command === 'run') {
  const { resolveConfig } = await import('./core/config.js');
  const { getInstalledCliTools } = await import('./core/module-registry.js');
  const config = resolveConfig();
  const tools = getInstalledCliTools(config);

  if (command === 'tools') {
    if (tools.length === 0) {
      console.log('No module shell utilities installed. Install modules first: claude-toolkit install');
      process.exit(0);
    }
    // Minimal, dependency-free color — only when writing to a real terminal and
    // NO_COLOR is unset (the de-facto standard). Pipes/CI/`| less` get plain text.
    const color = process.stdout.isTTY && !process.env.NO_COLOR;
    const bold = (s: string) => (color ? `\x1b[1m${s}\x1b[0m` : s);
    const cyan = (s: string) => (color ? `\x1b[1;36m${s}\x1b[0m` : s);   // tool name/usage
    const dim = (s: string) => (color ? `\x1b[2m${s}\x1b[0m` : s);       // run hint

    const width = Math.max(...tools.map(t => (t.usage || t.name).length));
    console.log('\n  ' + bold('Module shell utilities') + ' (also available under their own names on PATH):\n');
    for (const t of tools) {
      const label = (t.usage || t.name).padEnd(width);
      console.log(`    ${cyan(label)}   ${t.description}`);
    }
    console.log('\n  ' + dim('Run via:  claude-toolkit run <tool> [args…]   (or call <tool> directly)') + '\n');
    process.exit(0);
  }

  // run <tool> [args…]
  const [toolName, ...toolArgs] = args;
  if (!toolName) {
    console.error('usage: claude-toolkit run <tool> [args…]   (see: claude-toolkit tools)');
    process.exit(2);
  }
  const tool = tools.find(t => t.name === toolName);
  if (!tool) {
    console.error(`Unknown tool: ${toolName}. See 'claude-toolkit tools' for the list.`);
    process.exit(2);
  }
  if (!fs.existsSync(tool.path)) {
    console.error(`Tool script missing: ${tool.path}. Try: claude-toolkit install ${tool.moduleId}`);
    process.exit(1);
  }
  // Hand off: inherit stdio so interactive tools (fzf pickers, TUIs) work, and
  // propagate the tool's own exit code. spawnSync with the resolved script path.
  const { spawnSync } = await import('node:child_process');
  const res = spawnSync(tool.path, toolArgs, { stdio: 'inherit' });
  process.exit(res.status ?? (res.signal ? 1 : 0));
}

render(
  <App command={command} args={args} flags={cli.flags} />
);
