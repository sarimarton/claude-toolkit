import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'llm-cleanup-server',
  name: 'LLM Cleanup Server',
  description: 'Stateless localhost API over the Claude subscription that cleans up raw speech-to-text dictation using on-screen context. Engine for the dictation pipeline; reusable as a generic /cleanup endpoint.',
  longDescription:
    'A minimal Express server (express-only dependency) bound to 127.0.0.1:51733 exposing POST /cleanup { text, context } -> { text }. It shells out to the Claude CLI (claude -p) via execFile with a tightened output-only system prompt, so it is "an API surface over the Claude subscription" rather than a separately-billed API. Stateless by design: every request is independent (no session carry-over), which is correct for dictating into many parallel Claude Code tabs. Derived from the user\'s llm-server but stripped of session state, the Ink/React Tailscale TUI, and the OpenAI/LibreTranslate shims.',
  platform: 'darwin',
  dependencies: [],
  externals: [
    { binary: 'node', description: 'Node.js runtime for the Express server', required: true, installHint: 'brew install node (or nvm)' },
    { binary: 'npm', description: 'Installs the express dependency', required: true },
    {
      binary: 'claude',
      description: 'Claude CLI — the cleanup engine (claude -p)',
      required: true,
      installHint: 'Install Claude Code',
    },
  ],
  hooks: [],
  assets: [
    // The server JS (server/ dir) is deployed by the postInstall via cp -R from the
    // toolkit repo — it is a multi-file Node app, not a single rendered template.
    {
      source: 'com.sarim.llm-cleanup-server.plist.tpl',
      target: 'launchagents',
      filename: 'com.sarim.llm-cleanup-server.plist',
    },
    {
      source: 'llm-cleanup-postinstall.sh.tpl',
      target: 'scripts',
      filename: 'llm-cleanup-postinstall.sh',
      executable: true,
    },
  ],
  // Deploy the vendored server, npm install, resolve node/claude paths, bootstrap.
  postInstall: '{{scripts_dir}}/llm-cleanup-postinstall.sh',
  postUninstall:
    'launchctl bootout gui/$(id -u)/com.sarim.llm-cleanup-server 2>/dev/null; ' +
    'rm -rf {{install_dir}}/dictation/llm-cleanup-server',
};
