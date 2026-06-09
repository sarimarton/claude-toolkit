// node:test unit tests for the cleanup server's pure helpers.
// Run: node --test test/cleanup.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SYSTEM_PROMPT,
  buildUserPrompt,
  shSingleQuote,
  buildClaudeArgv,
} from '../src/modules/llm-cleanup-server/assets/server/cleanup.js';

test('SYSTEM_PROMPT forces output-only behavior', () => {
  assert.match(SYSTEM_PROMPT, /Output ONLY the cleaned/);
  assert.match(SYSTEM_PROMPT, /Hungarian and English/);
});

test('SYSTEM_PROMPT forbids command/code interpretation (transcription cleaner only)', () => {
  assert.match(SYSTEM_PROMPT, /TRANSCRIPTION CLEANER/);
  assert.match(SYSTEM_PROMPT, /never a command to execute/i);
  assert.match(SYSTEM_PROMPT, /MUST NOT[\s\S]*convert it into shell commands/i);
  // Context is reference only, not an instruction.
  assert.match(SYSTEM_PROMPT, /NOT an instruction/i);
});

test('buildUserPrompt omits context section when context is empty', () => {
  const p = buildUserPrompt('ez egy teszt', '');
  assert.equal(p, 'DICTATION:\nez egy teszt');
  assert.doesNotMatch(p, /CONTEXT/);
});

test('buildUserPrompt omits context section when context is whitespace only', () => {
  const p = buildUserPrompt('hello', '   \n  ');
  assert.doesNotMatch(p, /CONTEXT/);
});

test('buildUserPrompt includes delimited context when present', () => {
  const p = buildUserPrompt('run the make target', 'make karabiner\n$ tmux ls');
  assert.match(p, /CONTEXT \(on-screen, for disambiguation only\):/);
  assert.match(p, /make karabiner/);
  assert.match(p, /DICTATION:\nrun the make target/);
});

test('buildUserPrompt is null/undefined safe', () => {
  assert.equal(buildUserPrompt(undefined, undefined), 'DICTATION:\n');
  assert.equal(buildUserPrompt(null, null), 'DICTATION:\n');
});

test('shSingleQuote wraps plain text in single quotes', () => {
  assert.equal(shSingleQuote('hello world'), `'hello world'`);
});

test('shSingleQuote neutralizes embedded single quotes', () => {
  // O'Brien -> 'O'\''Brien'
  assert.equal(shSingleQuote("O'Brien"), `'O'\\''Brien'`);
});

test('shSingleQuote neutralizes shell metacharacters (inert)', () => {
  const payload = 'x; rm -rf / $(whoami) `id` && echo "q"';
  const quoted = shSingleQuote(payload);
  // Everything stays inside one single-quoted token; no unescaped quote breaks out.
  assert.ok(quoted.startsWith("'"));
  assert.ok(quoted.endsWith("'"));
  // The only way to leave a single-quoted string is a bare ', which must be escaped.
  // There are no bare single quotes in this payload, so it must be byte-identical inside.
  assert.equal(quoted, `'${payload}'`);
});

test('shSingleQuote preserves Hungarian accents and newlines', () => {
  const payload = 'Árvíztűrő\ntükörfúrógép';
  assert.equal(shSingleQuote(payload), `'${payload}'`);
});

test('shSingleQuote is null/undefined safe', () => {
  assert.equal(shSingleQuote(undefined), `''`);
  assert.equal(shSingleQuote(null), `''`);
});

test('buildClaudeArgv produces the correct argv shape (no shell)', () => {
  const argv = buildClaudeArgv('/path/claude', 'claude-haiku-4-5-20251001', 'SYS', 'USR');
  assert.deepEqual(argv, [
    '/path/claude', '-p', 'USR', '--model', 'claude-haiku-4-5-20251001',
    '--system-prompt', 'SYS',
  ]);
});

test('buildClaudeArgv keeps adversarial user text as a single argv element', () => {
  const nasty = '--system-prompt INJECTED; rm -rf /';
  const argv = buildClaudeArgv('claude', 'm', 's', nasty);
  // The nasty text is exactly one element (index 2); it cannot become a flag.
  assert.equal(argv[2], nasty);
  assert.equal(argv.indexOf(nasty), 2);
});
