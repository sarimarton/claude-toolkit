import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'stt-recovery',
  name: 'STT Recovery',
  description: 'Hungarian speech-to-text correction hook. Two-phase: fast LLM detection + parallel subagent investigation.',
  platform: 'any',
  dependencies: [
    { module: 'topic-markers', type: 'soft' },
  ],
  externals: [
    { binary: 'claude', description: 'Claude Code CLI', required: true },
    { binary: 'jq', description: 'JSON processor', required: true, installHint: 'brew install jq' },
  ],
  hooks: [
    {
      event: 'UserPromptSubmit',
      command: '{{hooks_dir}}/stt-recovery.sh',
      timeout: 120,
    },
  ],
  assets: [
    {
      source: 'stt-recovery.sh.tpl',
      target: 'hooks',
      filename: 'stt-recovery.sh',
      executable: true,
    },
  ],
};
