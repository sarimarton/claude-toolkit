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
    tmux: p.tmux || which('tmux', '/opt/homebrew/bin/tmux'),
    jq: p.jq || which('jq', '/opt/homebrew/bin/jq'),
    yq: p.yq || which('yq', '/opt/homebrew/bin/yq'),
    claude: p.claude || which('claude', path.join(HOME, '.local/bin/claude')),
    hs: p.hs || '/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs',
    home: HOME,
    installDir,
    repoDir: REPO_DIR,
    hooksDir,
    scriptsDir,
    commandsDir,
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
  for (const dir of [config.hooksDir, config.scriptsDir, config.commandsDir, config.swiftbarDir, config.helpersDir, config.launchAgentsDir]) {
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
    case 'launchagents': return config.launchAgentsDir;
    default: return config.installDir;
  }
}
