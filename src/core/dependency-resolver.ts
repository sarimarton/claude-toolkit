import type { ModuleManifest, ModuleDependency } from './types.js';
import { platformMatches } from './platform.js';

export interface ResolveResult {
  /** Modules in install order (topologically sorted) */
  order: string[];
  /** Modules auto-added as transitive hard dependencies */
  autoAdded: string[];
  /** Soft dependency warnings */
  softWarnings: string[];
  /** Platform-filtered modules (skipped) */
  platformSkipped: string[];
  /** Error message if resolution failed */
  error?: string;
}

/**
 * Resolve install order for a set of requested modules.
 * Automatically adds transitive hard dependencies.
 * Uses Kahn's algorithm for topological sort.
 */
export function resolveInstall(
  requested: string[],
  manifests: Map<string, ModuleManifest>,
): ResolveResult {
  const result: ResolveResult = {
    order: [],
    autoAdded: [],
    softWarnings: [],
    platformSkipped: [],
  };

  // Collect all needed modules (requested + transitive hard deps)
  const needed = new Set<string>();
  const queue = [...requested];

  while (queue.length > 0) {
    const id = queue.pop()!;
    if (needed.has(id)) continue;

    const manifest = manifests.get(id);
    if (!manifest) {
      result.error = `Unknown module: ${id}`;
      return result;
    }

    // Platform check
    if (!platformMatches(manifest.platform)) {
      result.platformSkipped.push(id);
      continue;
    }

    needed.add(id);

    for (const dep of manifest.dependencies) {
      if (dep.type === 'hard') {
        if (!needed.has(dep.module)) {
          queue.push(dep.module);
          if (!requested.includes(dep.module)) {
            result.autoAdded.push(dep.module);
          }
        }
      } else {
        // Soft dep: warn if not installed/requested
        if (!needed.has(dep.module) && !requested.includes(dep.module)) {
          result.softWarnings.push(
            `${id} has optional dependency on ${dep.module} (not selected)`,
          );
        }
      }
    }
  }

  // Kahn's algorithm: topological sort
  const inDegree = new Map<string, number>();
  const adj = new Map<string, string[]>();

  for (const id of needed) {
    inDegree.set(id, 0);
    adj.set(id, []);
  }

  for (const id of needed) {
    const manifest = manifests.get(id)!;
    for (const dep of manifest.dependencies) {
      if (dep.type === 'hard' && needed.has(dep.module)) {
        adj.get(dep.module)!.push(id);
        inDegree.set(id, (inDegree.get(id) || 0) + 1);
      }
    }
  }

  const zeroQueue: string[] = [];
  for (const [id, deg] of inDegree) {
    if (deg === 0) zeroQueue.push(id);
  }
  // Sort for deterministic output
  zeroQueue.sort();

  while (zeroQueue.length > 0) {
    const id = zeroQueue.shift()!;
    result.order.push(id);

    for (const next of adj.get(id) || []) {
      const newDeg = (inDegree.get(next) || 1) - 1;
      inDegree.set(next, newDeg);
      if (newDeg === 0) {
        // Insert sorted
        const idx = zeroQueue.findIndex(x => x > next);
        if (idx === -1) zeroQueue.push(next);
        else zeroQueue.splice(idx, 0, next);
      }
    }
  }

  // Check for cycles
  if (result.order.length < needed.size) {
    const remaining = [...needed].filter(id => !result.order.includes(id));
    result.error = `Circular dependency detected involving: ${remaining.join(', ')}`;
  }

  return result;
}

/**
 * Resolve uninstall order for a set of requested modules.
 * Returns reverse dependency cascade warnings.
 */
export function resolveUninstall(
  requested: string[],
  manifests: Map<string, ModuleManifest>,
  installedModules: Set<string>,
): ResolveResult {
  const result: ResolveResult = {
    order: [],
    autoAdded: [],
    softWarnings: [],
    platformSkipped: [],
  };

  // Find all installed modules that have hard deps on requested modules
  const toRemove = new Set(requested);
  let changed = true;

  while (changed) {
    changed = false;
    for (const id of installedModules) {
      if (toRemove.has(id)) continue;
      const manifest = manifests.get(id);
      if (!manifest) continue;

      for (const dep of manifest.dependencies) {
        if (dep.type === 'hard' && toRemove.has(dep.module)) {
          toRemove.add(id);
          result.autoAdded.push(id);
          changed = true;
          break;
        }
      }
    }
  }

  // Reverse topological order for uninstall (dependents first)
  const installResult = resolveInstall([...toRemove], manifests);
  result.order = installResult.order.reverse();

  return result;
}
