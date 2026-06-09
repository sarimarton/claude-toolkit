import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'dictation-pipeline',
  name: 'Dictation Pipeline',
  description: 'Async push-to-talk dictation into Claude Code panes: tmux-target capture → whisper.cpp → LLM cleanup → tmux send-keys. Parallel, target-bound, auto-ENTER.',
  longDescription:
    'Hold the push-to-talk chord to record mic audio while snapshotting the TARGET tmux pane id and its on-screen context. A resident launchd worker transcribes via a warm whisper-server (ggml-large-v3 held in-process), post-processes through the local llm-cleanup-server, then delivers with `tmux send-keys -l` to the EXACT pane (never the wrong tab) plus an optional Enter. A folder-as-queue dissolves the serial blocking of focus-bound dictation tools: capture is instant, so you can fire off the next dictation in another tab before the previous one finishes transcribing.',
  platform: 'darwin',
  dependencies: [
    { module: 'llm-cleanup-server', type: 'hard' },
  ],
  externals: [
    { binary: 'whisper-server', description: 'whisper.cpp resident server (holds ggml-large-v3 in-process)', required: true, installHint: 'brew install whisper-cpp' },
    { binary: 'whisper-cli', description: 'whisper.cpp CLI (per-job fallback)', required: false, installHint: 'brew install whisper-cpp' },
    { binary: 'ffmpeg', description: 'avfoundation mic capture', required: true, installHint: 'brew install ffmpeg' },
    { binary: 'tmux', description: 'capture-pane (context) + send-keys (delivery)', required: true, installHint: 'brew install tmux' },
    { binary: 'jq', description: 'JSON processor', required: true, installHint: 'brew install jq' },
    { binary: 'curl', description: 'whisper-server + cleanup HTTP calls', required: true },
  ],
  hooks: [],
  assets: [
    // Sourced libraries (not executable on their own).
    { source: 'dictation-queue.sh.tpl',   target: 'scripts', filename: 'dictation-queue.sh',   executable: false },
    { source: 'dictation-json.sh.tpl',    target: 'scripts', filename: 'dictation-json.sh',    executable: false },
    // Executable scripts.
    { source: 'capture-target.sh.tpl',    target: 'scripts', filename: 'capture-target.sh',    executable: true },
    { source: 'stop-record.sh.tpl',       target: 'scripts', filename: 'stop-record.sh',       executable: true },
    { source: 'dictation-worker.sh.tpl',  target: 'scripts', filename: 'dictation-worker.sh',  executable: true },
    { source: 'dictation-deliver.sh.tpl', target: 'scripts', filename: 'dictation-deliver.sh', executable: true },
    // Standalone AX-context reader (non-tmux apps): focused-element text via AppleScript.
    { source: 'ax-context.sh.tpl',        target: 'scripts', filename: 'ax-context.sh',        executable: true },
    { source: 'dictation-postinstall.sh.tpl', target: 'scripts', filename: 'dictation-postinstall.sh', executable: true },
    // Worker LaunchAgent.
    { source: 'com.sarim.dictation-worker.plist.tpl', target: 'launchagents', filename: 'com.sarim.dictation-worker.plist' },
  ],
  postInstall: '{{scripts_dir}}/dictation-postinstall.sh',
  postUninstall:
    'launchctl bootout gui/$(id -u)/com.sarim.dictation-worker 2>/dev/null; ' +
    'rm -rf {{install_dir}}/dictation/jobs {{install_dir}}/dictation/active {{install_dir}}/dictation/worker.lock.d',
};
