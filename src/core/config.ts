import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
import { parse as parseYaml } from 'yaml';
import type { ResolvedConfig } from './types.js';

const HOME = process.env.HOME || '/tmp';
const CONFIG_DIR = path.join(HOME, '.config', 'claude-toolkit');
// Three levels up from dist/core/config.js → the git repo root
const REPO_DIR = path.dirname(path.dirname(path.dirname(fileURLToPath(import.meta.url))));
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.yaml');

interface UserConfig {
  paths?: Record<string, string>;
  installDir?: string;
  accounts?: Array<{
    name: string;
    token: string;
    primary?: boolean;
  }>;
}

/** Find a binary in PATH, return full path or fallback */
function which(binary: string, fallback: string): string {
  try {
    return execSync(`which ${binary}`, { encoding: 'utf-8' }).trim();
  } catch {
    return fallback;
  }
}

/** Resolve the real Claude binary, never the toolkit's own claude shim.
 *  The stable-claude-bin module installs a `claude` shim in binDir and the user
 *  prepends binDir to PATH, so a bare `which claude` would return the shim —
 *  which then routes back through the launcher whose REAL_LINK is this value,
 *  forming an exec loop. Skip any PATH hit inside binDir and fall back to the
 *  install symlink so config.claude always points at the genuine binary. */
function whichClaude(binDir: string, fallback: string): string {
  const hit = which('claude', fallback);
  // Normalize both paths before the prefix check so alternate spellings of the
  // same location (trailing slash, //, /./, ..) can't slip the shim past the
  // guard. path.resolve collapses those; realpath would also follow symlinks but
  // the shim is a regular file, so resolve is enough and never throws on ENOENT.
  const normHit = path.resolve(hit);
  const normBin = path.resolve(binDir);
  return normHit === normBin || normHit.startsWith(normBin + path.sep) ? fallback : hit;
}

/** First existing Homebrew bin path for a tool, across the standard prefixes and
 *  a user-space prefix (~/homebrew on a sudo-less/MDM machine). Used as which()'s
 *  fallback when PATH lookup fails. */
function brewFallback(name: string): string {
  const candidates = [
    `${HOME}/homebrew/bin/${name}`,
    `${HOME}/.homebrew/bin/${name}`,
    `/opt/homebrew/bin/${name}`,
    `/usr/local/bin/${name}`,
  ];
  return candidates.find((c) => fs.existsSync(c)) ?? `/opt/homebrew/bin/${name}`;
}

/** Load user config from config.yaml (if exists) */
function loadUserConfig(): UserConfig {
  if (!fs.existsSync(CONFIG_FILE)) return {};
  try {
    const raw = fs.readFileSync(CONFIG_FILE, 'utf-8');
    return (parseYaml(raw) as UserConfig) || {};
  } catch {
    return {};
  }
}

/** Resolve all configuration paths via config.yaml overrides + auto-detection */
export function resolveConfig(): ResolvedConfig {
  const user = loadUserConfig();
  const p = user.paths || {};

  const installDir = user.installDir || CONFIG_DIR;
  const hooksDir = path.join(installDir, 'hooks');
  const scriptsDir = path.join(installDir, 'scripts');
  const binDir = path.join(installDir, 'bin');
  const commandsDir = path.join(installDir, 'commands');
  const claudeMdDir = path.join(installDir, 'claude-md');
  const helpersDir = path.join(installDir, 'helpers');
  const swiftbarDir = path.join(installDir, 'swiftbar');

  // SwiftBar plugin dir: where SwiftBar looks (macOS defaults or ~/.config/swiftbar).
  // This is separate from swiftbarDir (the deploy target inside installDir).
  let swiftbarPluginDir = path.join(HOME, '.config', 'swiftbar');
  try {
    const plist = execSync('defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null', { encoding: 'utf-8' }).trim();
    // Respect an existing SwiftBar plugin dir, but never our own internal deploy
    // dir: an earlier version pointed SwiftBar there, which evicted every other
    // plugin the user had (SwiftBar reads exactly one dir). That value is sticky
    // — config reads it back and install rewrites it — so ignoring it here lets
    // the next install repoint SwiftBar at the user's real dir and recover them.
    if (plist && plist !== swiftbarDir) swiftbarPluginDir = plist;
  } catch {
    // SwiftBar not installed or no preference set — use default
  }

  return {
    tmux: p.tmux || which('tmux', brewFallback('tmux')),
    jq: p.jq || which('jq', brewFallback('jq')),
    yq: p.yq || which('yq', brewFallback('yq')),
    claude: p.claude || whichClaude(binDir, path.join(HOME, '.local/bin/claude')),
    hs: p.hs || '/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs',
    home: HOME,
    installDir,
    repoDir: REPO_DIR,
    hooksDir,
    scriptsDir,
    binDir,
    commandsDir,
    claudeMdDir,
    skillsDir: path.join(HOME, '.claude', 'skills'),
    swiftbarDir,
    swiftbarPluginDir,
    helpersDir,
    launchAgentsDir: path.join(HOME, 'Library', 'LaunchAgents'),
    claudeDir: path.join(HOME, '.claude'),
    stateDir: path.join(HOME, 'Documents', 'state', 'claude-toolkit'),
    accounts: (user.accounts || []).map(a => ({
      name: a.name,
      token: a.token,
      primary: a.primary ?? false,
    })),
    configFile: CONFIG_FILE,
  };
}

/** Ensure all install directories exist */
export function ensureInstallDirs(config: ResolvedConfig): void {
  for (const dir of [config.hooksDir, config.scriptsDir, config.binDir, config.commandsDir, config.claudeMdDir, config.skillsDir, config.swiftbarDir, config.helpersDir, config.launchAgentsDir]) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/** Get the target directory for an asset target type */
export function getTargetDir(config: ResolvedConfig, target: string): string {
  switch (target) {
    case 'hooks': return config.hooksDir;
    case 'scripts': return config.scriptsDir;
    case 'bin': return config.binDir;
    case 'commands': return config.commandsDir;
    case 'skills': return config.skillsDir;
    case 'swiftbar': return config.swiftbarDir;
    case 'launchagents': return config.launchAgentsDir;
    default: return config.installDir;
  }
}
