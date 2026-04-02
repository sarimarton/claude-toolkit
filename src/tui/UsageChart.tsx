import React, { useEffect } from 'react';
import { Text } from 'ink';
import { execSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import { resolveConfig } from '../core/config.js';

export function UsageChart() {
  useEffect(() => {
    const config = resolveConfig();
    const script = path.join(config.scriptsDir, 'usage-chart.sh');

    if (!fs.existsSync(script)) {
      console.error('usage-chart.sh not found. Run: claude-toolkit install usage-monitor');
      process.exit(1);
    }

    try {
      execSync(`bash "${script}"`, { stdio: 'inherit' });
    } catch {
      process.exit(1);
    }
    process.exit(0);
  }, []);

  return <Text dimColor>Opening usage chart…</Text>;
}
