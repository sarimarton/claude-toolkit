import React, { useState, useEffect } from 'react';
import { Box, Text, useApp, useInput } from 'ink';
import { resolveConfig, ensureInstallDirs, getTargetDir } from '../core/config.js';
import { getAllManifests, getAllModuleStatuses, getInstalledModuleIds } from '../core/module-registry.js';
import { resolveInstall, resolveUninstall } from '../core/dependency-resolver.js';
import { registerHooks, unregisterHooks } from '../core/settings-manager.js';
import { buildVarMap, renderTemplate, installTemplate } from '../core/template-engine.js';
import { platformMatches } from '../core/platform.js';
import type { ModuleManifest, ModuleStatusInfo, ResolvedConfig } from '../core/types.js';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

type Mode = 'browse' | 'confirm-install' | 'confirm-uninstall' | 'executing' | 'done';

function getModulesDir(): string {
  const thisFile = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(thisFile), '..', 'modules');
}

export function ModuleTree() {
  const { exit } = useApp();
  const [statuses, setStatuses] = useState<ModuleStatusInfo[]>([]);
  const [cursor, setCursor] = useState(0);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [mode, setMode] = useState<Mode>('browse');
  const [message, setMessage] = useState('');

  useEffect(() => {
    const config = resolveConfig();
    setStatuses(getAllModuleStatuses(config));
  }, []);

  useInput((input, key) => {
    if (mode !== 'browse') {
      if (input === 'y' && mode === 'confirm-install') {
        executeInstall();
      } else if (input === 'y' && mode === 'confirm-uninstall') {
        executeUninstall();
      } else if (input === 'n' || key.escape) {
        setMode('browse');
        setMessage('');
      }
      if (mode === 'done' || mode === 'executing') {
        if (input === 'q' || key.escape) exit();
      }
      return;
    }

    if (key.upArrow || input === 'k') {
      setCursor(c => Math.max(0, c - 1));
    } else if (key.downArrow || input === 'j') {
      setCursor(c => Math.min(statuses.length - 1, c + 1));
    } else if (input === ' ') {
      const id = statuses[cursor]?.manifest.id;
      if (id) {
        setSelected(prev => {
          const next = new Set(prev);
          if (next.has(id)) next.delete(id);
          else next.add(id);
          return next;
        });
      }
    } else if (input === 'i') {
      // Install selected (or current if none selected)
      const toInstall = selected.size > 0 ? [...selected] : [statuses[cursor]?.manifest.id].filter(Boolean);
      if (toInstall.length === 0) return;
      const manifests = getAllManifests();
      const result = resolveInstall(toInstall, manifests);
      if (result.error) {
        setMessage(result.error);
        return;
      }
      setMessage(
        `Install: ${result.order.join(', ')}` +
        (result.autoAdded.length > 0 ? ` (auto: ${result.autoAdded.join(', ')})` : '') +
        ' — [y/n]?'
      );
      setMode('confirm-install');
    } else if (input === 'u') {
      // Uninstall selected (or current)
      const toUninstall = selected.size > 0 ? [...selected] : [statuses[cursor]?.manifest.id].filter(Boolean);
      if (toUninstall.length === 0) return;
      const manifests = getAllManifests();
      const installed = getInstalledModuleIds(resolveConfig());
      const result = resolveUninstall(toUninstall, manifests, installed);
      if (result.error) {
        setMessage(result.error);
        return;
      }
      setMessage(
        `Uninstall: ${result.order.join(', ')}` +
        (result.autoAdded.length > 0 ? ` (cascade: ${result.autoAdded.join(', ')})` : '') +
        ' — [y/n]?'
      );
      setMode('confirm-uninstall');
    } else if (input === 'q' || key.escape) {
      exit();
    }
  });

  function executeInstall() {
    setMode('executing');
    const toInstall = selected.size > 0 ? [...selected] : [statuses[cursor]?.manifest.id].filter(Boolean);
    const config = resolveConfig();
    ensureInstallDirs(config);
    const manifests = getAllManifests();
    const modulesDir = getModulesDir();
    const result = resolveInstall(toInstall, manifests);
    const vars = buildVarMap(config);

    let errors = 0;
    for (const id of result.order) {
      const manifest = manifests.get(id)!;
      try {
        for (const asset of manifest.assets) {
          const tplPath = path.join(modulesDir, manifest.id, 'assets', asset.source);
          const targetDir = getTargetDir(config, asset.target);
          installTemplate(tplPath, path.join(targetDir, asset.filename), vars, asset.executable !== false);
        }
        if (manifest.commands) {
          for (const cmd of manifest.commands) {
            const tplPath = path.join(modulesDir, manifest.id, 'assets', cmd.source);
            const targetDir = getTargetDir(config, cmd.target);
            installTemplate(tplPath, path.join(targetDir, cmd.filename), vars, cmd.executable === true);
          }
        }
        if (manifest.hooks.length > 0) {
          const resolvedHooks = manifest.hooks.map(h => ({ ...h, command: renderTemplate(h.command, vars) }));
          registerHooks(config, manifest.id, resolvedHooks);
        }
      } catch (err: any) {
        errors++;
        setMessage(`Error installing ${id}: ${err.message}`);
      }
    }

    setSelected(new Set());
    setStatuses(getAllModuleStatuses(config));
    setMessage(errors > 0 ? `Install finished with ${errors} errors` : `Installed ${result.order.length} modules. Press q to exit.`);
    setMode('done');
  }

  function executeUninstall() {
    setMode('executing');
    const toUninstall = selected.size > 0 ? [...selected] : [statuses[cursor]?.manifest.id].filter(Boolean);
    const config = resolveConfig();
    const manifests = getAllManifests();
    const installed = getInstalledModuleIds(config);
    const result = resolveUninstall(toUninstall, manifests, installed);

    for (const id of result.order) {
      const manifest = manifests.get(id)!;
      for (const asset of manifest.assets) {
        const targetDir = getTargetDir(config, asset.target);
        const p = path.join(targetDir, asset.filename);
        if (fs.existsSync(p)) fs.unlinkSync(p);
      }
      if (manifest.commands) {
        for (const cmd of manifest.commands) {
          const targetDir = getTargetDir(config, cmd.target);
          const p = path.join(targetDir, cmd.filename);
          if (fs.existsSync(p)) fs.unlinkSync(p);
        }
      }
      unregisterHooks(config, manifest.id);
    }

    setSelected(new Set());
    setStatuses(getAllModuleStatuses(config));
    setMessage(`Uninstalled ${result.order.length} modules. Press q to exit.`);
    setMode('done');
  }

  if (statuses.length === 0) return <Text dimColor>Loading...</Text>;

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold>Claude Toolkit</Text>
        <Text dimColor>  j/k: navigate  space: select  i: install  u: uninstall  q: quit</Text>
      </Box>

      {statuses.map((s, i) => {
        const isCursor = i === cursor;
        const isSelected = selected.has(s.manifest.id);
        const pm = platformMatches(s.manifest.platform);

        const statusIcon = s.status === 'installed' ? '✓' : s.status === 'partial' ? '◐' : '○';
        const statusColor = s.status === 'installed' ? 'green' : s.status === 'partial' ? 'yellow' : 'gray';

        return (
          <Box key={s.manifest.id}>
            <Text color={isCursor ? 'cyan' : undefined}>
              {isCursor ? '▸' : ' '}{isSelected ? '◉' : ' '} </Text>
            <Text color={statusColor}>{statusIcon} </Text>
            <Text bold={s.status === 'installed'} dimColor={!pm}>
              {s.manifest.id.padEnd(18)}
            </Text>
            <Text dimColor>{s.manifest.description.slice(0, 60)}</Text>
          </Box>
        );
      })}

      {message && (
        <Box marginTop={1}>
          <Text color={mode === 'done' ? 'green' : 'yellow'}>{message}</Text>
        </Box>
      )}
    </Box>
  );
}
