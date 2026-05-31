/** Account configuration for multi-account usage monitoring */
export interface AccountConfig {
  name: string;
  token: string;
  primary?: boolean;
}

/** Supported platforms */
export type Platform = 'darwin' | 'linux';

/** Module platform requirement */
export type PlatformReq = 'any' | 'darwin' | 'linux';

/** Dependency type */
export interface ModuleDependency {
  module: string;
  type: 'hard' | 'soft';
}

/** Hook event types supported by Claude Code */
export type HookEvent =
  | 'UserPromptSubmit'
  | 'PreToolUse'
  | 'PostToolUse'
  | 'Stop'
  | 'Notification'
  | 'SubagentStop';

/** A single hook registration in settings.json */
export interface HookEntry {
  type: 'command';
  command: string;
  timeout?: number;
}

/** A hook group as it appears in settings.json */
export interface HookGroup {
  matcher?: string;
  hooks: HookEntry[];
}

/** Hook registration for a module manifest */
export interface HookRegistration {
  event: HookEvent;
  matcher?: string;
  command: string;
  timeout?: number;
}

/** Asset target location */
export type AssetTarget = 'hooks' | 'scripts' | 'commands' | 'swiftbar' | 'launchagents';

/** Asset to install */
export interface AssetDefinition {
  /** Source template file relative to module's assets/ dir */
  source: string;
  /** Target subdirectory within ~/.config/claude-toolkit/ */
  target: AssetTarget;
  /** Output filename (without .tpl extension) */
  filename: string;
  /** Whether to set executable bit */
  executable?: boolean;
}

/** External dependency check */
export interface ExternalDependency {
  /** Binary name to check in PATH */
  binary: string;
  /** Human-readable description */
  description: string;
  /** Whether this is required (hard) or optional (soft) */
  required: boolean;
  /** Install hint for the user */
  installHint?: string;
  /**
   * Optional capability check run after the binary is found. A shell command
   * that must exit 0 for the dependency to be considered satisfied (e.g. verify
   * a CLI is authenticated or has a required scope). If it fails, `fixHint` is shown.
   */
  checkCommand?: string;
  /** Remediation hint shown when `checkCommand` fails (e.g. a command to run). */
  fixHint?: string;
}

/** Module manifest — the complete definition of a module */
export interface ModuleManifest {
  /** Unique module ID (directory name) */
  id: string;
  /** Human-readable name */
  name: string;
  /** Short description */
  description: string;
  /** Extended description shown in the TUI detail panel (newlines supported) */
  longDescription?: string;
  /** Platform requirement */
  platform: PlatformReq;
  /** Dependencies on other modules */
  dependencies: ModuleDependency[];
  /** External binary dependencies */
  externals: ExternalDependency[];
  /** Hook registrations */
  hooks: HookRegistration[];
  /** Asset files to install */
  assets: AssetDefinition[];
  /** Slash commands to install */
  commands?: AssetDefinition[];
  /** Command template to run after install (e.g. for custom build steps) */
  postInstall?: string;
  /** Command template to run after uninstall (e.g. for cleanup) */
  postUninstall?: string;
}

/** Resolved paths from config + auto-detection */
export interface ResolvedConfig {
  /** Path to tmux binary */
  tmux: string;
  /** Path to jq binary */
  jq: string;
  /** Path to yq binary */
  yq: string;
  /** Path to claude binary */
  claude: string;
  /** Path to Hammerspoon's hs CLI */
  hs: string;
  /** Home directory */
  home: string;
  /** Base install directory (~/.config/claude-toolkit) */
  installDir: string;
  /** Git repo directory (~/.local/share/claude-toolkit) */
  repoDir: string;
  /** Hooks directory */
  hooksDir: string;
  /** Scripts directory */
  scriptsDir: string;
  /** Commands directory */
  commandsDir: string;
  /** SwiftBar deploy directory (~/.config/claude-toolkit/swiftbar — where assets land) */
  swiftbarDir: string;
  /** SwiftBar plugin directory (where SwiftBar looks — contains symlinks to swiftbarDir) */
  swiftbarPluginDir: string;
  /** SwiftBar helpers directory */
  helpersDir: string;
  /** macOS LaunchAgents directory (~/Library/LaunchAgents) */
  launchAgentsDir: string;
  /** Claude settings directory (~/.claude) */
  claudeDir: string;
  /** Persistent timeline state directory (~/Documents/state/claude-toolkit) — survives reinstall */
  stateDir: string;
  /** Multi-account configurations */
  accounts: AccountConfig[];
  /** Path to the config file (for runtime reading by scripts) */
  configFile: string;
}

/** Sidecar manifest entry — tracks which module owns which hooks */
export interface SidecarEntry {
  moduleId: string;
  event: HookEvent;
  command: string;
  installedAt: string;
}

/** Sidecar asset entry — tracks installed files with content hashes */
export interface SidecarAssetEntry {
  moduleId: string;
  filename: string;
  target: AssetTarget;
  contentHash: string;
  installedAt: string;
}

/** Sidecar manifest file */
export interface SidecarManifest {
  version: number;
  entries: SidecarEntry[];
  assets?: SidecarAssetEntry[];
}

/** Module install status */
export type ModuleStatus = 'installed' | 'not_installed' | 'partial' | 'outdated';

/** Module status info for display */
export interface ModuleStatusInfo {
  manifest: ModuleManifest;
  status: ModuleStatus;
  installedAssets: string[];
  missingAssets: string[];
  registeredHooks: number;
  expectedHooks: number;
  platformMatch: boolean;
}
