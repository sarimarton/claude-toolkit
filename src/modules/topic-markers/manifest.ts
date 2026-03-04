import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'topic-markers',
  name: 'Topic Markers',
  description: 'Adds structured ($topic: | $completeness: | $state:) markers to every Claude response via UserPromptSubmit hook',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'jq', description: 'JSON processor', required: true, installHint: 'brew install jq' },
  ],
  hooks: [
    {
      event: 'UserPromptSubmit',
      command: '{{hooks_dir}}/topic-suffix.sh',
    },
  ],
  assets: [
    {
      source: 'topic-suffix.sh.tpl',
      target: 'hooks',
      filename: 'topic-suffix.sh',
      executable: true,
    },
  ],
};
