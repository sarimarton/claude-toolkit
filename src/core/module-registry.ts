import fs from 'node:fs';
import path from 'node:path';
import type { ModuleManifest, ModuleStatusInfo, ResolvedConfig } from './types.js';
import { getTargetDir } from './config.js';
import { getModuleHooks } from './settings-manager.js';
import { platformMatches } from './platform.js';

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
    info.status = 'installed';
  } else {
    info.status = 'partial';
  }

  return info;
}

/** Get status for all modules */
export function getAllModuleStatuses(config: ResolvedConfig): ModuleStatusInfo[] {
  return ALL_MANIFESTS.map(m => getModuleStatus(m, config));
}

/** Get set of currently installed module IDs */
export function getInstalledModuleIds(config: ResolvedConfig): Set<string> {
  const installed = new Set<string>();
  for (const m of ALL_MANIFESTS) {
    const status = getModuleStatus(m, config);
    if (status.status === 'installed' || status.status === 'partial') {
      installed.add(m.id);
    }
  }
  return installed;
}
