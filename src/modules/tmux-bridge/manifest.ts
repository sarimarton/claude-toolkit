import type { ModuleManifest } from '../../core/types.js';

export const manifest: ModuleManifest = {
  id: 'tmux-bridge',
  name: 'Tmux Bridge (interactive headless)',
  description:
    'Drop-in replacement for `claude -p` that drives an interactive Claude TUI inside a throwaway ' +
    'tmux session, so headless/background work bills against the interactive subscription bucket ' +
    'instead of the separate metered headless-credit pool. Injection and parsing are 100% inference-free.',
  longDescription:
    'From 2026-06-15, headless invocations (`claude -p`, GitHub-Actions "cloud" runs) bill against a ' +
    'separate metered credit pool rather than the interactive subscription bucket. The auto-dev pipeline ' +
    'calls `claude -p`, so it would draw from the wrong pool.\n\n' +
    'claude-tmux works around this by driving a REAL interactive Claude Code session programmatically: it ' +
    'spawns a fresh, isolated tmux session running `claude --dangerously-skip-permissions`, injects the ' +
    'prompt via tmux send-keys, streams the pane via pipe-pane, and slices the answer out between fixed ' +
    'ASCII sentinel markers. Because the session is interactive, the work bills as interactive usage.\n\n' +
    'The whole inject→detect→parse path is deterministic — NO model inference is used to drive or read the ' +
    'TUI — so it stays purely a subscription-bucket run. Completion is detected by the closing sentinel in ' +
    'the raw stream (primary) or the TUI returning to an idle prompt with the spinner gone (backup).\n\n' +
    'It mirrors the `claude -p` surface we use (-p, --model, --output-format json, --json-schema) and, in ' +
    'JSON mode, emits {"structured_output": <obj>} so callers parsing with `jq .structured_output…` (e.g. ' +
    'auto-dev) work unchanged — a byte-compatible drop-in. Prefers the claude-stable launcher when the ' +
    'stable-claude-bin module is installed, else falls back to the version symlink.\n\n' +
    'Trade-off: an interactive session is serial — there is no parallel `-p` fan-out — so a high-concurrency ' +
    'auto-dev matrix would need a session pool. The single-shot path here covers the common case.',
  platform: 'any',
  dependencies: [
    { module: 'stable-claude-bin', type: 'soft' },
  ],
  externals: [
    { binary: 'tmux', description: 'Terminal multiplexer', required: true, installHint: 'brew install tmux' },
    { binary: 'claude', description: 'Claude Code CLI', required: true },
    { binary: 'python3', description: 'Python 3 (deterministic stream parsing)', required: true },
  ],
  hooks: [],
  assets: [
    {
      source: 'claude-tmux.sh.tpl',
      target: 'scripts',
      filename: 'claude-tmux',
      executable: true,
    },
    {
      // Deterministic stream parser + schema validator, invoked by claude-tmux.
      // Standalone (not inlined) so it can be unit-tested — see test_parse_answer.py.
      source: 'parse_answer.py',
      target: 'scripts',
      filename: 'claude-tmux-parse.py',
      executable: false,
    },
  ],
  // Expose `claude-tmux` on PATH (~/.local/bin is what setup.sh adds), so it can be
  // used as a `claude -p` drop-in from anywhere. The parser (claude-tmux-parse.py)
  // is an internal helper called by absolute path, so it is NOT symlinked.
  postInstall:
    'mkdir -p "$HOME/.local/bin" && ln -sf "{{scripts_dir}}/claude-tmux" "$HOME/.local/bin/claude-tmux" && ' +
    'echo "tmux-bridge installed. claude-tmux is on PATH — use it as a \\`claude -p\\` drop-in. ' +
    'To route auto-dev through it, set modules.autoDev.useTmuxBridge: true in config.yaml."',
  postUninstall: 'rm -f "$HOME/.local/bin/claude-tmux"',
};
