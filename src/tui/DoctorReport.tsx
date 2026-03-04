import React, { useEffect, useState } from 'react';
import { Box, Text, useApp } from 'ink';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { resolveConfig } from '../core/config.js';
import { getAllModuleStatuses } from '../core/module-registry.js';
import { readSidecar, readSettings } from '../core/settings-manager.js';
import type { ModuleStatusInfo, ResolvedConfig } from '../core/types.js';

interface Check {
  label: string;
  status: 'ok' | 'warn' | 'error';
  detail?: string;
}

function checkBinary(name: string, hint?: string): Check {
  try {
    execSync(`which ${name}`, { encoding: 'utf-8' });
    return { label: `${name} found`, status: 'ok' };
  } catch {
    return {
      label: `${name} not found`,
      status: 'error',
      detail: hint || `Install ${name}`,
    };
  }
}

export function DoctorReport() {
  const { exit } = useApp();
  const [checks, setChecks] = useState<Check[]>([]);

  useEffect(() => {
    const results: Check[] = [];
    const config = resolveConfig();

    // 1. Check basic externals
    results.push(checkBinary('node'));
    results.push(checkBinary('tmux', 'brew install tmux'));
    results.push(checkBinary('jq', 'brew install jq'));
    results.push(checkBinary('claude'));

    // 2. Check install directory
    if (fs.existsSync(config.installDir)) {
      results.push({ label: `Install dir exists: ${config.installDir}`, status: 'ok' });
    } else {
      results.push({ label: `Install dir missing: ${config.installDir}`, status: 'warn', detail: 'Run claude-toolkit install to create it' });
    }

    // 3. Check settings.json
    const settingsPath = path.join(config.claudeDir, 'settings.json');
    if (fs.existsSync(settingsPath)) {
      try {
        JSON.parse(fs.readFileSync(settingsPath, 'utf-8'));
        results.push({ label: 'settings.json valid JSON', status: 'ok' });
      } catch {
        results.push({ label: 'settings.json invalid JSON', status: 'error', detail: 'Fix or restore settings.json' });
      }
    } else {
      results.push({ label: 'settings.json not found', status: 'warn' });
    }

    // 4. Check sidecar manifest consistency
    const sidecar = readSidecar(config);
    const settings = readSettings(config);
    const hooksObj = settings.hooks as Record<string, any[]> | undefined;

    let orphanedSidecar = 0;
    for (const entry of sidecar.entries) {
      // Check if the command still exists in settings.json
      let found = false;
      if (hooksObj) {
        for (const groups of Object.values(hooksObj)) {
          for (const group of groups) {
            for (const h of group.hooks || []) {
              if (h.command === entry.command) found = true;
            }
          }
        }
      }
      if (!found) orphanedSidecar++;
    }

    if (orphanedSidecar > 0) {
      results.push({
        label: `${orphanedSidecar} orphaned sidecar entries`,
        status: 'warn',
        detail: 'Sidecar references hooks not in settings.json. Re-install affected modules.',
      });
    } else {
      results.push({ label: 'Sidecar manifest consistent', status: 'ok' });
    }

    // 5. Check module statuses
    const statuses = getAllModuleStatuses(config);
    const partial = statuses.filter(s => s.status === 'partial');
    if (partial.length > 0) {
      results.push({
        label: `${partial.length} partially installed modules`,
        status: 'warn',
        detail: `Modules: ${partial.map(s => s.manifest.id).join(', ')}. Run upgrade to fix.`,
      });
    } else {
      results.push({ label: 'All installed modules complete', status: 'ok' });
    }

    // 6. Check installed module externals
    const installed = statuses.filter(s => s.status === 'installed' || s.status === 'partial');
    for (const s of installed) {
      for (const ext of s.manifest.externals) {
        const check = checkBinary(ext.binary, ext.installHint);
        if (check.status !== 'ok') {
          results.push({
            label: `${s.manifest.id}: ${ext.binary} ${ext.required ? 'required' : 'optional'}`,
            status: ext.required ? 'error' : 'warn',
            detail: ext.installHint,
          });
        }
      }
    }

    // 7. Check asset files exist for installed modules
    for (const s of installed) {
      if (s.missingAssets.length > 0) {
        results.push({
          label: `${s.manifest.id}: missing assets: ${s.missingAssets.join(', ')}`,
          status: 'error',
          detail: 'Run claude-toolkit upgrade to reinstall',
        });
      }
    }

    setChecks(results);
    setTimeout(() => exit(), 100);
  }, []);

  const icon = (status: Check['status']) => {
    switch (status) {
      case 'ok': return '✓';
      case 'warn': return '⚠';
      case 'error': return '✕';
    }
  };

  const clr = (status: Check['status']) => {
    switch (status) {
      case 'ok': return 'green';
      case 'warn': return 'yellow';
      case 'error': return 'red';
    }
  };

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold>Claude Toolkit — Doctor</Text>
      </Box>

      {checks.map((check, i) => (
        <Box key={i} flexDirection="column">
          <Box>
            <Text color={clr(check.status)}>{icon(check.status)} {check.label}</Text>
          </Box>
          {check.detail && (
            <Box marginLeft={4}>
              <Text dimColor>{check.detail}</Text>
            </Box>
          )}
        </Box>
      ))}

      <Box marginTop={1}>
        <Text dimColor>
          {checks.filter(c => c.status === 'ok').length} ok,{' '}
          {checks.filter(c => c.status === 'warn').length} warnings,{' '}
          {checks.filter(c => c.status === 'error').length} errors
        </Text>
      </Box>
    </Box>
  );
}
