import fs from 'node:fs';
import path from 'node:path';
import type { HookRegistration, HookGroup, HookEvent, SidecarManifest, SidecarEntry, ResolvedConfig } from './types.js';

function settingsPath(config: ResolvedConfig): string {
  return path.join(config.claudeDir, 'settings.json');
}

function sidecarPath(config: ResolvedConfig): string {
  return path.join(config.claudeDir, '.claude-toolkit-manifest.json');
}

/** Read the Claude settings.json */
export function readSettings(config: ResolvedConfig): Record<string, unknown> {
  const p = settingsPath(config);
  if (!fs.existsSync(p)) return {};
  return JSON.parse(fs.readFileSync(p, 'utf-8'));
}

/** Write the Claude settings.json (atomic: write to .tmp then rename) */
export function writeSettings(config: ResolvedConfig, settings: Record<string, unknown>): void {
  const p = settingsPath(config);
  const tmp = p + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(settings, null, 2) + '\n');
  fs.renameSync(tmp, p);
}

/** Read the sidecar manifest */
export function readSidecar(config: ResolvedConfig): SidecarManifest {
  const p = sidecarPath(config);
  if (!fs.existsSync(p)) return { version: 1, entries: [] };
  try {
    return JSON.parse(fs.readFileSync(p, 'utf-8'));
  } catch {
    return { version: 1, entries: [] };
  }
}

/** Write the sidecar manifest */
export function writeSidecar(config: ResolvedConfig, manifest: SidecarManifest): void {
  const p = sidecarPath(config);
  fs.writeFileSync(p, JSON.stringify(manifest, null, 2) + '\n');
}

/**
 * Register hooks for a module into settings.json.
 * Appends hook entries to the appropriate event arrays.
 * Records ownership in the sidecar manifest.
 */
export function registerHooks(
  config: ResolvedConfig,
  moduleId: string,
  hooks: HookRegistration[],
): void {
  // Unregister existing hooks first to make this idempotent (no duplicates on reinstall)
  unregisterHooks(config, moduleId);

  const settings = readSettings(config);
  const sidecar = readSidecar(config);

  if (!settings.hooks) {
    settings.hooks = {};
  }
  const hooksObj = settings.hooks as Record<string, HookGroup[]>;

  for (const hook of hooks) {
    const event = hook.event;
    if (!hooksObj[event]) {
      hooksObj[event] = [];
    }

    const group: HookGroup = {
      hooks: [{
        type: 'command',
        command: hook.command,
        ...(hook.timeout ? { timeout: hook.timeout } : {}),
      }],
    };

    if (hook.matcher !== undefined) {
      group.matcher = hook.matcher;
    }

    hooksObj[event].push(group);

    // Record in sidecar
    sidecar.entries.push({
      moduleId,
      event,
      command: hook.command,
      installedAt: new Date().toISOString(),
    });
  }

  writeSettings(config, settings);
  writeSidecar(config, sidecar);
}

/**
 * Unregister all hooks owned by a module.
 * Uses the sidecar manifest to identify which entries to remove.
 */
export function unregisterHooks(
  config: ResolvedConfig,
  moduleId: string,
): void {
  const settings = readSettings(config);
  const sidecar = readSidecar(config);

  // Find commands owned by this module
  const ownedCommands = new Set(
    sidecar.entries
      .filter(e => e.moduleId === moduleId)
      .map(e => e.command),
  );

  if (ownedCommands.size === 0) return;

  const hooksObj = settings.hooks as Record<string, HookGroup[]> | undefined;
  if (!hooksObj) return;

  // Remove matching hook entries from each event
  for (const event of Object.keys(hooksObj)) {
    hooksObj[event] = hooksObj[event].filter(group => {
      // Keep groups that have at least one hook not owned by this module
      group.hooks = group.hooks.filter(h => !ownedCommands.has(h.command));
      return group.hooks.length > 0;
    });
    // Remove empty event arrays
    if (hooksObj[event].length === 0) {
      delete hooksObj[event];
    }
  }

  // Remove empty hooks object
  if (Object.keys(hooksObj).length === 0) {
    delete settings.hooks;
  }

  // Remove from sidecar
  sidecar.entries = sidecar.entries.filter(e => e.moduleId !== moduleId);

  writeSettings(config, settings);
  writeSidecar(config, sidecar);
}

/** Get hook commands registered for a specific module (from sidecar) */
export function getModuleHooks(config: ResolvedConfig, moduleId: string): SidecarEntry[] {
  const sidecar = readSidecar(config);
  return sidecar.entries.filter(e => e.moduleId === moduleId);
}

/** Check if a specific hook command is registered in settings.json */
export function isHookRegistered(config: ResolvedConfig, command: string): boolean {
  const settings = readSettings(config);
  const hooksObj = settings.hooks as Record<string, HookGroup[]> | undefined;
  if (!hooksObj) return false;

  for (const groups of Object.values(hooksObj)) {
    for (const group of groups) {
      for (const hook of group.hooks) {
        if (hook.command === command) return true;
      }
    }
  }
  return false;
}
