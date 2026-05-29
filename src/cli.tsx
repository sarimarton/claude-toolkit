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

  Options
    --help       Show this help
    --version    Show version
    --yes, -y    Skip confirmation prompts
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

render(
  <App command={command} args={args} flags={cli.flags} />
);
