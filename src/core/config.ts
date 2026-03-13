import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { parse as parseYaml } from 'yaml';
import type { ResolvedConfig } from './types.js';

const HOME = process.env.HOME || '/tmp';
const CONFIG_DIR = path.join(HOME, '.config', 'claude-toolkit');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.yaml');

interface UserConfig {
  paths?: Record<string, string>;
  installDir?: string;
}

/** Find a binary in PATH, return full path or fallback */
function which(binary: string, fallback: string): string {
  try {
    return execSync(`which ${binary}`, { encoding: 'utf-8' }).trim();
  } catch {
    return fallback;
  }
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
  const commandsDir = path.join(installDir, 'commands');
  const helpersDir = path.join(installDir, 'helpers');

  // SwiftBar: read actual plugin directory from macOS defaults, fall back to ~/.config/swiftbar
  let swiftbarDir = path.join(HOME, '.config', 'swiftbar');
  try {
    const plist = execSync('defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null', { encoding: 'utf-8' }).trim();
    if (plist) swiftbarDir = plist;
  } catch {
    // SwiftBar not installed or no preference set — use default
  }

  return {
    tmux: p.tmux || which('tmux', '/opt/homebrew/bin/tmux'),
    jq: p.jq || which('jq', '/opt/homebrew/bin/jq'),
    claude: p.claude || which('claude', path.join(HOME, '.local/bin/claude')),
    hs: p.hs || '/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs',
    home: HOME,
    installDir,
    hooksDir,
    scriptsDir,
    commandsDir,
    swiftbarDir,
    helpersDir,
    claudeDir: path.join(HOME, '.claude'),
  };
}

/** Ensure all install directories exist */
export function ensureInstallDirs(config: ResolvedConfig): void {
  for (const dir of [config.hooksDir, config.scriptsDir, config.commandsDir, config.swiftbarDir, config.helpersDir]) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/** Get the target directory for an asset target type */
export function getTargetDir(config: ResolvedConfig, target: string): string {
  switch (target) {
    case 'hooks': return config.hooksDir;
    case 'scripts': return config.scriptsDir;
    case 'commands': return config.commandsDir;
    case 'swiftbar': return config.swiftbarDir;
    default: return config.installDir;
  }
}
