#!/usr/bin/env node
import meow from 'meow';
import React from 'react';
import { render } from 'ink';
import { App } from './tui/App.js';

const cli = meow(`
  Usage
    $ claude-toolkit                  Interactive dashboard
    $ claude-toolkit list             List all modules with status
    $ claude-toolkit install [mod..]  Install modules (auto-resolves deps)
    $ claude-toolkit uninstall         Dashboard (select + u to uninstall)
    $ claude-toolkit uninstall [mod..] Uninstall specific modules
    $ claude-toolkit uninstall all     Uninstall all modules
    $ claude-toolkit status           Per-module health check
    $ claude-toolkit doctor           Full integrity audit
    $ claude-toolkit upgrade          Re-template installed modules
    $ claude-toolkit chart            Open usage chart in browser

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

render(
  <App command={command} args={args} flags={cli.flags} />
);
