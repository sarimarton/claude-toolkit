import fs from 'node:fs';
import path from 'node:path';
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
    hooks_dir: config.hooksDir,
    scripts_dir: config.scriptsDir,
    commands_dir: config.commandsDir,
    swiftbar_dir: config.swiftbarDir,
    helpers_dir: config.helpersDir,
    claude_dir: config.claudeDir,
    chart_plan_cost: String(config.chartPlanCost),
    chart_api_rate: String(config.chartApiRate),
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
