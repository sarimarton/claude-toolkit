import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'topic-markers',
  name: 'Topic Markers',
  description: 'Adds structured ($topic: | $m: | $pct: | $q:) markers to every Claude response via UserPromptSubmit hook',
  platform: 'any',
  dependencies: [],
  externals: [
    { binary: 'jq', description: 'JSON processor', required: true, installHint: 'brew install jq' },
    { binary: 'fzf', description: 'Fuzzy picker for crt (topic-based session resume)', required: false, installHint: 'brew install fzf' },
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
    {
      // crt — resume a past session by fuzzy-matching its $topic marker.
      source: 'claude-resume-topic.sh.tpl',
      target: 'scripts',
      filename: 'claude-resume-topic.sh',
      executable: true,
    },
  ],
  // Expose the resume CLI as `crt` on PATH (~/.local/bin is what setup.sh adds).
  postInstall: 'mkdir -p "$HOME/.local/bin" && ln -sf "{{scripts_dir}}/claude-resume-topic.sh" "$HOME/.local/bin/crt"',
  postUninstall: 'rm -f "$HOME/.local/bin/crt"',
};
