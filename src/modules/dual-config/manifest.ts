import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'dual-config',
  name: 'Dual Config',
  description:
    'Isolates OAuth and API key auth into separate ~/.claude (OAuth, default) and ~/.claude-apikey config dirs. ' +
    'Provides a claude() shell function that auto-routes based on ANTHROPIC_API_KEY env var.',
  platform: 'any',
  dependencies: [],
  externals: [
    {
      binary: 'jq',
      description: 'JSON processor for settings sync',
      required: true,
      installHint: 'brew install jq',
    },
    {
      binary: 'claude',
      description: 'Claude Code CLI',
      required: true,
    },
  ],
  hooks: [],
  assets: [
    {
      source: 'claude-fn.sh.tpl',
      target: 'scripts',
      filename: 'claude-fn.sh',
      executable: true,
    },
    {
      source: 'setup-apikey-dir.sh.tpl',
      target: 'scripts',
      filename: 'setup-apikey-dir.sh',
      executable: true,
    },
  ],
};
