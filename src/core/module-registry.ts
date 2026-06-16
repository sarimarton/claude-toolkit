import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ModuleManifest, ModuleStatusInfo, ResolvedConfig } from './types.js';
import { getTargetDir } from './config.js';
import { getModuleHooks, getModuleAssetHashes } from './settings-manager.js';
import { platformMatches } from './platform.js';
import { buildVarMap, renderTemplateFile, contentHash } from './template-engine.js';

// Static imports of all module manifests
import { manifest as topicMarkers } from '../modules/topic-markers/manifest.js';
import { manifest as tmuxTitles } from '../modules/tmux-titles/manifest.js';
import { manifest as tmuxSessions } from '../modules/tmux-sessions/manifest.js';
import { manifest as usageMonitor } from '../modules/usage-monitor/manifest.js';
import { manifest as menubar } from '../modules/menubar/manifest.js';
import { manifest as notifications } from '../modules/notifications/manifest.js';
import { manifest as sounds } from '../modules/sounds/manifest.js';
import { manifest as sttRecovery } from '../modules/stt-recovery/manifest.js';
import { manifest as ghosttyTmux } from '../modules/ghostty-tmux/manifest.js';
import { manifest as vscodeTmux } from '../modules/vscode-tmux/manifest.js';
import { manifest as dualConfig } from '../modules/dual-config/manifest.js';
import { manifest as vscodeTerminalTopic } from '../modules/vscode-terminal-topic/manifest.js';
import { manifest as autoDev } from '../modules/auto-dev/manifest.js';
import { manifest as autoDevInstaller } from '../modules/auto-dev-installer/manifest.js';
import { manifest as stableClaudeBin } from '../modules/stable-claude-bin/manifest.js';
import { manifest as tmuxBridge } from '../modules/tmux-bridge/manifest.js';
import { manifest as llmCleanupServer } from '../modules/llm-cleanup-server/manifest.js';
import { manifest as dictationPipeline } from '../modules/dictation-pipeline/manifest.js';
import { manifest as ultraresume } from '../modules/ultraresume/manifest.js';

/** All module manifests */
const ALL_MANIFESTS: ModuleManifest[] = [
  topicMarkers,
  tmuxTitles,
  tmuxSessions,
  usageMonitor,
  menubar,
  notifications,
  sounds,
  sttRecovery,
  ghosttyTmux,
  vscodeTmux,
  dualConfig,
  vscodeTerminalTopic,
  autoDev,
  autoDevInstaller,
  stableClaudeBin,
  tmuxBridge,
  llmCleanupServer,
  dictationPipeline,
  ultraresume,
];

/** Get all manifests as a Map keyed by module ID */
export function getAllManifests(): Map<string, ModuleManifest> {
  const map = new Map<string, ModuleManifest>();
  for (const m of ALL_MANIFESTS) {
    map.set(m.id, m);
  }
  return map;
}

/** Get a single manifest by ID */
export function getManifest(id: string): ModuleManifest | undefined {
  return ALL_MANIFESTS.find(m => m.id === id);
}

function getModulesDir(): string {
  const thisFile = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(thisFile), '..', 'modules');
}

/** Check the install status of a module */
export function getModuleStatus(manifest: ModuleManifest, config: ResolvedConfig): ModuleStatusInfo {
  const info: ModuleStatusInfo = {
    manifest,
    status: 'not_installed',
    installedAssets: [],
    missingAssets: [],
    registeredHooks: 0,
    expectedHooks: manifest.hooks.length,
    platformMatch: platformMatches(manifest.platform),
  };

  // Check assets
  for (const asset of manifest.assets) {
    const targetDir = getTargetDir(config, asset.target);
    const targetFile = path.join(targetDir, asset.filename);
    if (fs.existsSync(targetFile)) {
      info.installedAssets.push(asset.filename);
    } else {
      info.missingAssets.push(asset.filename);
    }
  }

  // Check commands
  if (manifest.commands) {
    for (const cmd of manifest.commands) {
      const targetDir = getTargetDir(config, cmd.target);
      const targetFile = path.join(targetDir, cmd.filename);
      if (fs.existsSync(targetFile)) {
        info.installedAssets.push(cmd.filename);
      } else {
        info.missingAssets.push(cmd.filename);
      }
    }
  }

  // Check hooks via sidecar
  const sidecarHooks = getModuleHooks(config, manifest.id);
  info.registeredHooks = sidecarHooks.length;

  // Determine status
  const totalAssets = manifest.assets.length + (manifest.commands?.length || 0);
  if (info.installedAssets.length === 0 && info.registeredHooks === 0) {
    info.status = 'not_installed';
  } else if (
    info.installedAssets.length === totalAssets &&
    info.registeredHooks === info.expectedHooks
  ) {
    // Check for outdated: compare content hashes
    const storedHashes = getModuleAssetHashes(config, manifest.id);
    if (storedHashes.length > 0) {
      const vars = buildVarMap(config);
      const modulesDir = getModulesDir();
      const allAssets = [...manifest.assets, ...(manifest.commands || [])];
      const hashMap = new Map(storedHashes.map(h => [h.filename, h.contentHash]));

      for (const asset of allAssets) {
        const storedHash = hashMap.get(asset.filename);
        if (!storedHash) {
          info.status = 'outdated';
          break;
        }
        try {
          const tplPath = path.join(modulesDir, manifest.id, 'assets', asset.source);
          const rendered = renderTemplateFile(tplPath, vars);
          if (contentHash(rendered) !== storedHash) {
            info.status = 'outdated';
            break;
          }
        } catch {
          // Template read failed — can't determine, keep as installed
        }
      }
      if (info.status !== 'outdated') {
        info.status = 'installed';
      }
    } else {
      // No hashes stored (pre-hash installation) — treat as installed
      info.status = 'installed';
    }
  } else {
    info.status = 'partial';
  }

  return info;
}

/** Get status for all modules */
export function getAllModuleStatuses(config: ResolvedConfig): ModuleStatusInfo[] {
  return ALL_MANIFESTS.map(m => getModuleStatus(m, config));
}

/** A CLI tool resolved for listing/running: manifest fields + script path + owner. */
export interface ResolvedCliTool {
  name: string;
  description: string;
  usage?: string;
  /** Absolute path to the runnable script under the scripts dir. */
  path: string;
  /** The module that ships this tool. */
  moduleId: string;
}

/**
 * Aggregate the CLI tools contributed by INSTALLED modules. Pure over its inputs
 * (manifests, the installed-id set, the scripts dir) so it is unit-testable; the
 * config-bound wrapper getInstalledCliTools() feeds it live values. Sorted by
 * name for a stable listing.
 */
export function collectCliTools(
  manifests: Pick<ModuleManifest, 'id' | 'cli'>[],
  installedIds: Set<string>,
  scriptsDir: string,
): ResolvedCliTool[] {
  const tools: ResolvedCliTool[] = [];
  for (const m of manifests) {
    if (!m.cli || !installedIds.has(m.id)) continue;
    for (const t of m.cli) {
      tools.push({
        name: t.name,
        description: t.description,
        usage: t.usage,
        path: path.join(scriptsDir, t.script),
        moduleId: m.id,
      });
    }
  }
  return tools.sort((a, b) => a.name.localeCompare(b.name));
}

/** Live CLI tools for all currently-installed modules. */
export function getInstalledCliTools(config: ResolvedConfig): ResolvedCliTool[] {
  return collectCliTools(ALL_MANIFESTS, getInstalledModuleIds(config), config.scriptsDir);
}

/** Get set of currently installed module IDs */
export function getInstalledModuleIds(config: ResolvedConfig): Set<string> {
  const installed = new Set<string>();
  for (const m of ALL_MANIFESTS) {
    const status = getModuleStatus(m, config);
    if (status.status === 'installed' || status.status === 'partial' || status.status === 'outdated') {
      installed.add(m.id);
    }
  }
  return installed;
}
