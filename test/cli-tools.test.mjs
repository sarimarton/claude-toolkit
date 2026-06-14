// node:test unit tests for the CLI-tool aggregation pure helper.
// Run: node --test test/cli-tools.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collectCliTools } from '../dist/core/module-registry.js';

const MANIFESTS = [
  {
    id: 'topic-markers',
    cli: [{ name: 'crt', description: 'Resume a past session by $topic', script: 'claude-resume-topic.sh', usage: 'crt <query…>' }],
  },
  {
    id: 'ultraresume',
    cli: [{ name: 'claude-ultraresume', description: 'Resume the prior session from scrollback', script: 'claude-ultraresume.sh' }],
  },
  { id: 'no-cli-module' },                 // module with no cli field at all
  { id: 'not-installed-mod', cli: [{ name: 'ghost', description: 'should be hidden', script: 'ghost.sh' }] },
];

const SCRIPTS = '/opt/scripts';

test('collectCliTools: returns tools only for installed modules, with resolved paths', () => {
  const installed = new Set(['topic-markers', 'ultraresume']);
  const tools = collectCliTools(MANIFESTS, installed, SCRIPTS);
  const names = tools.map(t => t.name).sort();
  assert.deepEqual(names, ['claude-ultraresume', 'crt']);

  const crt = tools.find(t => t.name === 'crt');
  assert.equal(crt.description, 'Resume a past session by $topic');
  assert.equal(crt.usage, 'crt <query…>');
  assert.equal(crt.path, '/opt/scripts/claude-resume-topic.sh');
  assert.equal(crt.moduleId, 'topic-markers');
});

test('collectCliTools: excludes tools from not-installed modules', () => {
  const installed = new Set(['topic-markers', 'ultraresume']);
  const tools = collectCliTools(MANIFESTS, installed, SCRIPTS);
  assert.equal(tools.find(t => t.name === 'ghost'), undefined);
});

test('collectCliTools: a module without a cli field contributes nothing', () => {
  const installed = new Set(['no-cli-module']);
  const tools = collectCliTools(MANIFESTS, installed, SCRIPTS);
  assert.deepEqual(tools, []);
});

test('collectCliTools: sorted by name for stable listing', () => {
  const installed = new Set(['topic-markers', 'ultraresume']);
  const tools = collectCliTools(MANIFESTS, installed, SCRIPTS);
  const names = tools.map(t => t.name);
  assert.deepEqual(names, [...names].sort());
});

test('collectCliTools: empty when nothing installed', () => {
  assert.deepEqual(collectCliTools(MANIFESTS, new Set(), SCRIPTS), []);
});
