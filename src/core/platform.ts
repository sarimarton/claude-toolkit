import os from 'node:os';
import type { Platform, PlatformReq } from './types.js';

/** Detect current platform */
export function currentPlatform(): Platform {
  const p = os.platform();
  if (p === 'darwin') return 'darwin';
  return 'linux';
}

/** Check if a module's platform requirement matches the current platform */
export function platformMatches(req: PlatformReq): boolean {
  if (req === 'any') return true;
  return req === currentPlatform();
}

/** Get architecture */
export function arch(): string {
  return os.arch();
}
