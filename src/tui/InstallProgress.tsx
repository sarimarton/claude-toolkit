import React, { useEffect, useState } from 'react';
import { Box, Text, useApp } from 'ink';
import { resolveConfig, ensureInstallDirs, getTargetDir } from '../core/config.js';
import { getAllManifests, getInstalledModuleIds, getModuleStatus } from '../core/module-registry.js';
import { resolveInstall, resolveUninstall } from '../core/dependency-resolver.js';
import { registerHooks, unregisterHooks, recordAssetHashes, removeAssetHashes } from '../core/settings-manager.js';
import { applyTmuxConfig, removeTmuxConfig } from '../core/tmux-config-manager.js';
import { applyClaudeMdBlock, removeClaudeMdBlock, ensureClaudeMdImport, removeClaudeMdImport } from '../core/claude-md-manager.js';
import { buildVarMap, renderTemplate, installTemplate, renderTemplateFile, contentHash } from '../core/template-engine.js';
import type { ModuleManifest, ResolvedConfig } from '../core/types.js';
import { execSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

interface Props {
  modules: string[];
  autoConfirm?: boolean;
  uninstall?: boolean;
  upgrade?: boolean;
}

type StepStatus = 'pending' | 'running' | 'done' | 'error';

interface Step {
  moduleId: string;
  label: string;
  status: StepStatus;
  error?: string;
}

function getModulesDir(): string {
  const thisFile = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(thisFile), '..', 'modules');
}

function doInstall(manifest: ModuleManifest, config: ResolvedConfig, modulesDir: string): void {
  const vars = buildVarMap(config);
  const assetHashes: { filename: string; target: import('../core/types.js').AssetTarget; contentHash: string }[] = [];

  // Install assets
  for (const asset of manifest.assets) {
    const tplPath = path.join(modulesDir, manifest.id, 'assets', asset.source);
    const targetDir = getTargetDir(config, asset.target);
    const targetPath = path.join(targetDir, asset.filename);
    installTemplate(tplPath, targetPath, vars, asset.executable !== false);
    const rendered = renderTemplateFile(tplPath, vars);
    assetHashes.push({ filename: asset.filename, target: asset.target, contentHash: contentHash(rendered) });
  }

  // Install commands
  if (manifest.commands) {
    for (const cmd of manifest.commands) {
      const tplPath = path.join(modulesDir, manifest.id, 'assets', cmd.source);
      const targetDir = getTargetDir(config, cmd.target);
      const targetPath = path.join(targetDir, cmd.filename);
      installTemplate(tplPath, targetPath, vars, cmd.executable === true);
      const rendered = renderTemplateFile(tplPath, vars);
      assetHashes.push({ filename: cmd.filename, target: cmd.target, contentHash: contentHash(rendered) });
    }
  }

  // Record asset hashes in sidecar
  recordAssetHashes(config, manifest.id, assetHashes);

  // Register hooks (resolve template vars in commands)
  if (manifest.hooks.length > 0) {
    const resolvedHooks = manifest.hooks.map(h => ({
      ...h,
      command: renderTemplate(h.command, vars),
    }));
    registerHooks(config, manifest.id, resolvedHooks);
  }

  // Write tmux drop-in (resolve template vars), the tmux analogue of hook registration
  if (manifest.tmuxConf) {
    const tc = manifest.tmuxConf;
    applyTmuxConfig(config, manifest.id, {
      lines: tc.lines.map(l => renderTemplate(l, vars)),
      overrides: tc.overrides?.map(o => renderTemplate(o, vars)),
    });
  }

  // Write CLAUDE.md policy drop-ins (render the block body with template vars) and
  // auto-wire the @import into the canonical ~/.claude/CLAUDE.md (marked, idempotent,
  // augment-only — see claude-md-manager.ts).
  if (manifest.claudeMdBlocks) {
    for (const block of manifest.claudeMdBlocks) {
      const tplPath = path.join(modulesDir, manifest.id, 'assets', block.source);
      const body = renderTemplateFile(tplPath, vars);
      applyClaudeMdBlock(config, manifest.id, block.sectionId, body);
      ensureClaudeMdImport(config, manifest.id, block.sectionId);
    }
  }

  // Run post-install command
  if (manifest.postInstall) {
    const cmd = renderTemplate(manifest.postInstall, vars);
    execSync(cmd, { stdio: 'pipe' });
  }
}

function doUninstall(manifest: ModuleManifest, config: ResolvedConfig): void {
  // Remove assets
  for (const asset of manifest.assets) {
    const targetDir = getTargetDir(config, asset.target);
    const targetPath = path.join(targetDir, asset.filename);
    if (fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
  }

  // Remove commands
  if (manifest.commands) {
    for (const cmd of manifest.commands) {
      const targetDir = getTargetDir(config, cmd.target);
      const targetPath = path.join(targetDir, cmd.filename);
      if (fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
    }
  }

  // Remove asset hashes and unregister hooks
  removeAssetHashes(config, manifest.id);
  unregisterHooks(config, manifest.id);

  // Remove tmux.conf marker block + restore any in-place edits
  if (manifest.tmuxConf) {
    removeTmuxConfig(config, manifest.id);
  }

  // Remove CLAUDE.md policy drop-ins + their auto-wired @import lines
  if (manifest.claudeMdBlocks) {
    for (const block of manifest.claudeMdBlocks) {
      removeClaudeMdBlock(config, manifest.id, block.sectionId);
      removeClaudeMdImport(config, manifest.id, block.sectionId);
    }
  }

  // Run post-uninstall command
  if (manifest.postUninstall) {
    const vars = buildVarMap(config);
    const cmd = renderTemplate(manifest.postUninstall, vars);
    try {
      execSync(cmd, { stdio: 'pipe' });
    } catch {
      // Best-effort cleanup
    }
  }
}

export function InstallProgress({ modules, autoConfirm, uninstall, upgrade }: Props) {
  const { exit } = useApp();
  const [steps, setSteps] = useState<Step[]>([]);
  const [phase, setPhase] = useState<'resolving' | 'executing' | 'done' | 'error'>('resolving');
  const [message, setMessage] = useState('');

  useEffect(() => {
    const config = resolveConfig();
    ensureInstallDirs(config);
    const manifests = getAllManifests();
    const modulesDir = getModulesDir();

    if (upgrade) {
      // Re-install all currently installed modules
      const installed = getInstalledModuleIds(config);
      if (installed.size === 0) {
        setMessage('No modules installed to upgrade.');
        setPhase('done');
        setTimeout(() => exit(), 100);
        return;
      }
      modules = [...installed];
    }

    if (uninstall && modules.length === 1 && modules[0] === 'all') {
      const installed = getInstalledModuleIds(config);
      if (installed.size === 0) {
        setMessage('No modules installed.');
        setPhase('done');
        setTimeout(() => exit(), 100);
        return;
      }
      modules = [...installed];
    }

    if (modules.length === 0 && !upgrade) {
      setMessage('No modules specified. Use: claude-toolkit install <module>');
      setPhase('done');
      setTimeout(() => exit(), 100);
      return;
    }

    let result;
    if (uninstall) {
      const installed = getInstalledModuleIds(config);
      result = resolveUninstall(modules, manifests, installed);
    } else {
      result = resolveInstall(modules, manifests);
    }

    if (result.error) {
      setMessage(result.error);
      setPhase('error');
      setTimeout(() => exit(), 100);
      return;
    }

    if (result.autoAdded.length > 0) {
      setMessage(
        uninstall
          ? `Cascade: also removing ${result.autoAdded.join(', ')}`
          : `Auto-adding dependencies: ${result.autoAdded.join(', ')}`
      );
    }

    // Build step list
    const actionLabel = uninstall ? 'Uninstall' : 'Install';
    const newSteps: Step[] = result.order.map(id => ({
      moduleId: id,
      label: `${actionLabel} ${id}`,
      status: 'pending' as StepStatus,
    }));

    setSteps(newSteps);
    setPhase('executing');

    // Execute steps sequentially
    let currentSteps = [...newSteps];
    for (let i = 0; i < currentSteps.length; i++) {
      currentSteps = currentSteps.map((s, j) =>
        j === i ? { ...s, status: 'running' as StepStatus } : s
      );
      setSteps([...currentSteps]);

      const manifest = manifests.get(currentSteps[i].moduleId);
      if (!manifest) {
        currentSteps = currentSteps.map((s, j) =>
          j === i ? { ...s, status: 'error' as StepStatus, error: 'Manifest not found' } : s
        );
        setSteps([...currentSteps]);
        continue;
      }

      try {
        if (uninstall) {
          doUninstall(manifest, config);
        } else {
          doInstall(manifest, config, modulesDir);
        }
        currentSteps = currentSteps.map((s, j) =>
          j === i ? { ...s, status: 'done' as StepStatus } : s
        );
      } catch (err: any) {
        currentSteps = currentSteps.map((s, j) =>
          j === i ? { ...s, status: 'error' as StepStatus, error: err.message } : s
        );
      }
      setSteps([...currentSteps]);
    }

    setPhase('done');
    setTimeout(() => exit(), 100);
  }, []);

  const icon = (status: StepStatus) => {
    switch (status) {
      case 'pending': return '○';
      case 'running': return '◉';
      case 'done': return '✓';
      case 'error': return '✕';
    }
  };

  const color = (status: StepStatus) => {
    switch (status) {
      case 'pending': return 'gray';
      case 'running': return 'cyan';
      case 'done': return 'green';
      case 'error': return 'red';
    }
  };

  return (
    <Box flexDirection="column">
      {message && (
        <Box marginBottom={1}>
          <Text color={phase === 'error' ? 'red' : 'yellow'}>{message}</Text>
        </Box>
      )}

      {steps.map((step, i) => (
        <Box key={i}>
          <Text color={color(step.status)}>{icon(step.status)} {step.label}</Text>
          {step.error && <Text color="red"> — {step.error}</Text>}
        </Box>
      ))}

      {phase === 'done' && steps.length > 0 && (
        <Box marginTop={1}>
          <Text color="green">
            {uninstall ? 'Uninstall' : 'Install'} complete.
            {' '}{steps.filter(s => s.status === 'done').length}/{steps.length} succeeded.
          </Text>
        </Box>
      )}
    </Box>
  );
}
