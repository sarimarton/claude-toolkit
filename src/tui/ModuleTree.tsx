import React, { useState, useEffect } from 'react';
import { Box, Text, useApp, useInput, useStdout } from 'ink';
import { resolveConfig, ensureInstallDirs, getTargetDir } from '../core/config.js';
import { getAllManifests, getAllModuleStatuses, getInstalledModuleIds } from '../core/module-registry.js';
import { resolveInstall, resolveUninstall } from '../core/dependency-resolver.js';
import { registerHooks, unregisterHooks } from '../core/settings-manager.js';
import { buildVarMap, renderTemplate, installTemplate } from '../core/template-engine.js';
import { platformMatches } from '../core/platform.js';
import type { ModuleManifest, ModuleStatusInfo, ResolvedConfig } from '../core/types.js';
import { execSync } from 'node:child_process';
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
  const { stdout } = useStdout();
  const [statuses, setStatuses] = useState<ModuleStatusInfo[]>([]);
  const [cursor, setCursor] = useState(0);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [mode, setMode] = useState<Mode>('browse');
  const [message, setMessage] = useState('');

  const cols = stdout?.columns ?? 100;
  const listWidth = Math.min(28, Math.floor(cols * 0.3));
  const detailWidth = cols - listWidth - 5; // 5 for borders/padding

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
    } else if (input === 'a') {
      // Toggle select all / deselect all
      setSelected(prev => {
        if (prev.size === statuses.length) {
          return new Set();
        }
        return new Set(statuses.map(s => s.manifest.id));
      });
    } else if (input === 'i') {
      executeInstall();
    } else if (input === 'u') {
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
    const toInstall = selected.size > 0 ? [...selected] : [statuses[cursor]?.manifest.id].filter(Boolean);
    if (toInstall.length === 0) return;
    const manifests = getAllManifests();
    const result = resolveInstall(toInstall, manifests);
    if (result.error) {
      setMessage(result.error);
      return;
    }

    // Immediate feedback — then defer heavy work so Ink can render
    setMode('executing');
    setMessage('Installing…');

    setTimeout(() => {
      const config = resolveConfig();
      ensureInstallDirs(config);
      const modulesDir = getModulesDir();
      const vars = buildVarMap(config);

      let errors = 0;
      const errorDetails: string[] = [];
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
          if (manifest.postInstall) {
            const cmd = renderTemplate(manifest.postInstall, vars);
            execSync(cmd, { stdio: 'pipe' });
          }
        } catch (err: any) {
          errors++;
          errorDetails.push(`${id}: ${err.message}`);
        }
      }

      setSelected(new Set());
      setStatuses(getAllModuleStatuses(config));
      setMessage(errors > 0 ? `Install finished with ${errors} error(s): ${errorDetails.join('; ')}` : `Installed ${result.order.length} modules.`);
      setMode('done');
      setTimeout(() => exit(), errors > 0 ? 3000 : 500);
    }, 0);
  }

  function executeUninstall() {
    setMode('executing');
    const toUninstall = selected.size > 0 ? [...selected] : [statuses[cursor]?.manifest.id].filter(Boolean);
    const config = resolveConfig();
    const manifests = getAllManifests();
    const installed = getInstalledModuleIds(config);
    const result = resolveUninstall(toUninstall, manifests, installed);

    const vars = buildVarMap(config);
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
      if (manifest.postUninstall) {
        try {
          const cmd = renderTemplate(manifest.postUninstall, vars);
          execSync(cmd, { stdio: 'pipe' });
        } catch {
          // Best-effort cleanup
        }
      }
    }

    setSelected(new Set());
    setStatuses(getAllModuleStatuses(config));
    setMessage(`Uninstalled ${result.order.length} modules.`);
    setTimeout(() => exit(), 500);
    setMode('done');
  }

  if (statuses.length === 0) return <Text dimColor>Loading...</Text>;

  const current = statuses[cursor];
  const deps = current?.manifest.dependencies ?? [];
  const exts = current?.manifest.externals ?? [];

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold>Claude Toolkit</Text>
        <Text dimColor>  j/k: navigate  space: select  a: all  i: install  u: uninstall  q: quit</Text>
      </Box>

      <Box>
        {/* Left panel: module list */}
        <Box flexDirection="column" width={listWidth}>
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
                <Text bold={isCursor} dimColor={!pm}>
                  {s.manifest.id}
                </Text>
              </Box>
            );
          })}
        </Box>

        {/* Separator */}
        <Box flexDirection="column" marginLeft={1} marginRight={1}>
          <Text dimColor>│</Text>
          {statuses.map((_, i) => (
            <Text key={i} dimColor>│</Text>
          ))}
        </Box>

        {/* Right panel: detail for current module */}
        <Box flexDirection="column" width={detailWidth}>
          <Text bold color="cyan">{current?.manifest.name}</Text>
          <Text dimColor>
            {current?.manifest.platform !== 'any' ? `(${current?.manifest.platform} only)  ` : ''}
            {current?.status === 'installed' ? '✓ installed' : current?.status === 'partial' ? '◐ partial' : '○ not installed'}
          </Text>
          <Text> </Text>
          <Text wrap="wrap">{current?.manifest.description}</Text>
          {deps.length > 0 && (
            <>
              <Text> </Text>
              <Text dimColor>Dependencies: {deps.map(d => d.module + (d.type === 'soft' ? ' (optional)' : '')).join(', ')}</Text>
            </>
          )}
          {exts.length > 0 && (
            <>
              <Text> </Text>
              <Text dimColor>Requires: {exts.map(e => e.binary + (e.required ? '' : ' (optional)')).join(', ')}</Text>
            </>
          )}
        </Box>
      </Box>

      <Box marginTop={1}>
        <Text dimColor>{selected.size > 0 ? `${selected.size} selected` : ' '}</Text>
      </Box>

      {message && (
        <Box marginTop={1}>
          <Text color={mode === 'done' ? 'green' : 'yellow'}>{message}</Text>
        </Box>
      )}
    </Box>
  );
}
