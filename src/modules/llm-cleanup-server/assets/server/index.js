#!/usr/bin/env node
// Dictation cleanup server — a stateless localhost API over the Claude subscription.
//
// Design (per the agreed plan):
//  * STATELESS: every /cleanup call is independent. There is NO session carry-over
//    (the user dictates into many parallel Claude tabs; a single linear session
//    would be wrong). All context arrives in the request body.
//  * The engine is the Claude CLI (`claude -p`) — this is "an API surface over the
//    subscription", not a separate API-key billed endpoint.
//  * Binds to 127.0.0.1 only. No Tailscale, no Ink TUI, no OpenAI shim — just /cleanup.
//
// Env:
//   PORT        (default 51733)
//   CLAUDE_BIN  (default 'claude' on PATH; the launchd plist injects the stable
//               launcher path because `claude` is a zsh function, not a PATH binary)
//   CLEANUP_MODEL (default claude-haiku-4-5-20251001 — fast)

import express from 'express';
import { spawn } from 'node:child_process';
import { SYSTEM_PROMPT, buildUserPrompt, buildClaudeArgv } from './cleanup.js';

const PORT = parseInt(process.env.PORT || '51733', 10);
const CLAUDE_BIN = process.env.CLAUDE_BIN || 'claude';
// Default to Sonnet: live A/B showed Haiku truncates/garbles the cleanup and
// over-edits, while Sonnet keeps the wording verbatim and only fixes transcription
// errors — the disciplined behavior this task needs. ~2x slower than Haiku but
// quality is the whole point (this is the "watershed" the on-screen context buys).
const MODEL = process.env.CLEANUP_MODEL || 'claude-sonnet-4-6';
const TIMEOUT_MS = 60000;

// runClaude(user) -> Promise<string>. Uses spawn (no shell) so the user prompt is
// a single argv element. We CLOSE the child's stdin immediately ('ignore'): the
// prompt is passed via -p, and `claude` otherwise blocks ~3s waiting on stdin for
// piped input ("no stdin data received in 3s"). Closing stdin makes it return
// straight away.
function runClaude(user) {
  const [, ...args] = buildClaudeArgv(CLAUDE_BIN, MODEL, SYSTEM_PROMPT, user);
  return new Promise((resolve, reject) => {
    const child = spawn(CLAUDE_BIN, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '', err = '';
    const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error('cleanup timeout')); }, TIMEOUT_MS);
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { err += d; });
    child.on('error', e => { clearTimeout(timer); reject(e); });
    child.on('close', code => {
      clearTimeout(timer);
      if (code !== 0) return reject(new Error(err.trim() || `claude exited ${code}`));
      resolve(out.trim());
    });
  });
}

const app = express();
app.use(express.json({ limit: '2mb' }));

app.get('/health', (_req, res) => res.json({ status: 'ok', model: MODEL }));

// POST /cleanup  { text, context? }  ->  { text }
app.post('/cleanup', async (req, res) => {
  const { text, context } = req.body || {};
  if (typeof text !== 'string' || !text.trim()) {
    return res.status(400).json({ error: 'missing or empty "text"' });
  }
  try {
    const cleaned = await runClaude(buildUserPrompt(text, context));
    // Fail-safe: if the model returned nothing usable, echo the raw text so the
    // dictation is never lost downstream.
    res.json({ text: cleaned || text });
  } catch (e) {
    // The worker is fail-open (delivers raw on error), so a 500 here is acceptable;
    // we still log for diagnosis.
    console.error('[cleanup] error:', e.message);
    res.status(500).json({ error: e.message, text });
  }
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`[cleanup] listening on http://127.0.0.1:${PORT} (model=${MODEL}, bin=${CLAUDE_BIN})`);
});
