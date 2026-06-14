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
export type AssetTarget = 'hooks' | 'scripts' | 'commands' | 'swiftbar' | 'launchagents' | 'bin';

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

/**
 * A user-facing shell utility a module ships (e.g. `crt`, `claude-tmux`). These
 * are aggregated under `claude-toolkit tools` (discovery) and runnable via
 * `claude-toolkit run <name>` — without replacing the module's own PATH symlink,
 * which keeps working. The manifest is the single source of truth for what tools
 * exist; the `script` is the asset filename under the module's scripts dir.
 */
export interface CliTool {
  /** Canonical tool name as shown in listings (e.g. "crt", "claude-ultraresume"). */
  name: string;
  /** One-line description of what it does. */
  description: string;
  /** The installed script filename under config.scriptsDir (e.g. "claude-resume-topic.sh"). */
  script: string;
  /** Optional usage hint shown in listings (e.g. "crt <query…>"). */
  usage?: string;
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
  /** User-facing shell utilities, surfaced under `claude-toolkit tools` / `run`. */
  cli?: CliTool[];
  /**
   * tmux config additions. The toolkit does NOT edit the user's hand-written,
   * version-controlled ~/.config/tmux/tmux.conf. Instead it writes a generated,
   * machine-specific drop-in file (~/.config/tmux/tmux.conf.d/claude-toolkit-<id>.conf)
   * that the main config sources at the end via a single stable glob line:
   *   source-file -q ~/.config/tmux/tmux.conf.d/*.conf
   * The user adds that one line once (version-controlled, path-relative). Because
   * tmux uses last-write-wins for `set`, drop-in lines can OVERRIDE earlier
   * settings — so even "edits" to existing directives are expressed as plain
   * append lines, no in-place rewriting. Install = write the drop-in; uninstall =
   * delete it. Only applied if the main tmux.conf exists (augment, don't create).
   */
  tmuxConf?: TmuxConfigPatch;
  /** Command template to run after install (e.g. for custom build steps) */
  postInstall?: string;
  /** Command template to run after uninstall (e.g. for cleanup) */
  postUninstall?: string;
}

/**
 * The tmux config lines a module contributes, written verbatim into its drop-in
 * file (after template-var resolution: {{tmux}}, {{scripts_dir}}, …).
 *
 * `lines` are new directives (e.g. a `set-hook -ga client-attached …`).
 * `overrides` are directives that supersede a setting from the main tmux.conf
 * (e.g. re-`set`ting @resurrect-processes without "~claude"). They are written
 * the same way — the only distinction is intent/ordering: overrides go LAST in
 * the drop-in so they win. Kept as a separate field so the generated file can
 * group + comment them, making it obvious which lines deliberately shadow the
 * user's config.
 */
export interface TmuxConfigPatch {
  /** New directives the module adds (template vars allowed). */
  lines: string[];
  /** Directives that override a main-config setting via last-write-wins. */
  overrides?: string[];
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
  /** Bin directory (~/.config/claude-toolkit/bin) — meant to be prepended to PATH */
  binDir: string;
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
