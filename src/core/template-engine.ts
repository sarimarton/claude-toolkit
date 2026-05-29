import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import type { ResolvedConfig } from './types.js';

/** Build the variable map from resolved config */
export function buildVarMap(config: ResolvedConfig): Record<string, string> {
  return {
    tmux: config.tmux,
    jq: config.jq,
    yq: config.yq,
    claude: config.claude,
    hs: config.hs,
    home: config.home,
    install_dir: config.installDir,
    repo_dir: config.repoDir,
    hooks_dir: config.hooksDir,
    scripts_dir: config.scriptsDir,
    commands_dir: config.commandsDir,
    swiftbar_dir: config.swiftbarDir,
    swiftbar_plugin_dir: config.swiftbarPluginDir,
    helpers_dir: config.helpersDir,
    launch_agents_dir: config.launchAgentsDir,
    claude_dir: config.claudeDir,
    chart_plan_cost: String(config.chartPlanCost),
    chart_api_rate: String(config.chartApiRate),
    poll_interval: String(config.pollIntervalSeconds),
    config_file: config.configFile,
  };
}

/** Render a template string by replacing all {{var}} placeholders */
export function renderTemplate(template: string, vars: Record<string, string>): string {
  const rendered = template.replace(/\{\{(\w+)\}\}/g, (match, key: string) => {
    if (key in vars) return vars[key];
    throw new Error(`Unresolved template variable: ${match}`);
  });
  return rendered;
}

/** Read a .tpl file and render it */
export function renderTemplateFile(tplPath: string, vars: Record<string, string>): string {
  const template = fs.readFileSync(tplPath, 'utf-8');
  return renderTemplate(template, vars);
}

/** Compute SHA-256 hash of content */
export function contentHash(content: string): string {
  return createHash('sha256').update(content).digest('hex');
}

/** Render a template file and write the result to the target path */
export function installTemplate(
  tplPath: string,
  targetPath: string,
  vars: Record<string, string>,
  executable: boolean = true,
): void {
  const rendered = renderTemplateFile(tplPath, vars);
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, rendered, { mode: executable ? 0o755 : 0o644 });
}
