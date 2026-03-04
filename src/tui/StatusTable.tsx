import React, { useEffect, useState } from 'react';
import { Box, Text, useApp } from 'ink';
import { resolveConfig } from '../core/config.js';
import { getAllModuleStatuses } from '../core/module-registry.js';
import type { ModuleStatusInfo } from '../core/types.js';

interface Props {
  detailed?: boolean;
}

const STATUS_ICONS: Record<string, string> = {
  installed: '✓',
  not_installed: '○',
  partial: '◐',
  outdated: '↻',
};

const STATUS_COLORS: Record<string, string> = {
  installed: 'green',
  not_installed: 'gray',
  partial: 'yellow',
  outdated: 'cyan',
};

export function StatusTable({ detailed = false }: Props) {
  const { exit } = useApp();
  const [statuses, setStatuses] = useState<ModuleStatusInfo[]>([]);

  useEffect(() => {
    const config = resolveConfig();
    setStatuses(getAllModuleStatuses(config));
    // Non-interactive command: exit after render
    setTimeout(() => exit(), 100);
  }, []);

  if (statuses.length === 0) {
    return <Text dimColor>Loading...</Text>;
  }

  // Calculate column widths
  const maxId = Math.max(...statuses.map(s => s.manifest.id.length));
  const maxName = Math.max(...statuses.map(s => s.manifest.name.length));

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold>Claude Toolkit — Modules</Text>
      </Box>

      {/* Header */}
      <Box>
        <Text dimColor>  {'Status'.padEnd(16)} {'Module'.padEnd(maxId + 2)} {'Name'.padEnd(maxName + 2)} Platform  Deps</Text>
      </Box>

      {statuses.map(s => {
        const icon = STATUS_ICONS[s.status] || '?';
        const color = STATUS_COLORS[s.status] as any;
        const deps = s.manifest.dependencies.map(d =>
          `${d.module}${d.type === 'soft' ? '?' : ''}`
        ).join(', ') || '—';

        return (
          <Box key={s.manifest.id} flexDirection="column">
            <Box>
              <Text color={color}>  {icon} </Text>
              <Text color={color}>{s.status.padEnd(16)}</Text>
              <Text bold={s.status === 'installed'}>
                {s.manifest.id.padEnd(maxId + 2)}
              </Text>
              <Text>{s.manifest.name.padEnd(maxName + 2)}</Text>
              <Text dimColor={!s.platformMatch}>
                {s.manifest.platform.padEnd(10)}
              </Text>
              <Text dimColor>{deps}</Text>
            </Box>

            {detailed && s.status !== 'not_installed' && (
              <Box marginLeft={4} flexDirection="column">
                <Text dimColor>
                  Assets: {s.installedAssets.length}/{s.manifest.assets.length + (s.manifest.commands?.length || 0)}
                  {' '}Hooks: {s.registeredHooks}/{s.expectedHooks}
                </Text>
                {s.missingAssets.length > 0 && (
                  <Text color="yellow">  Missing: {s.missingAssets.join(', ')}</Text>
                )}
              </Box>
            )}
          </Box>
        );
      })}

      <Box marginTop={1}>
        <Text dimColor>
          {statuses.filter(s => s.status === 'installed').length} installed, {' '}
          {statuses.filter(s => s.status === 'not_installed').length} available
        </Text>
      </Box>
    </Box>
  );
}
