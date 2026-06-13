// node:test unit tests for the SwiftBar version gate used by the doctor.
// Run: node --test test/swiftbar-version.test.mjs
//
// Why this matters: SwiftBar 2.0.1 has upstream bug #442 (VisibleCC=0 persists,
// icon vanishes). The fix is in build >= 576 (2.1.0-beta-2). A stray
// `brew upgrade --cask swiftbar` can silently downgrade to 2.0.1, so the doctor
// flags it. This tests the pure decision: given a build number, is it OK?
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { evaluateSwiftBarBuild, SWIFTBAR_MIN_BUILD } from '../dist/core/swiftbar-version.js';

test('build at the minimum is OK', () => {
  const r = evaluateSwiftBarBuild(SWIFTBAR_MIN_BUILD);
  assert.equal(r.status, 'ok');
});

test('newer build is OK', () => {
  assert.equal(evaluateSwiftBarBuild(SWIFTBAR_MIN_BUILD + 10).status, 'ok');
});

test('the buggy 2.0.1 build (536) is a warning, not ok', () => {
  const r = evaluateSwiftBarBuild(536);
  assert.equal(r.status, 'warn');
  assert.match(r.detail, /2\.1|#442|pin/i);
});

test('a missing/unparseable build (0) warns', () => {
  assert.equal(evaluateSwiftBarBuild(0).status, 'warn');
});

test('null (app not found) returns null — caller decides whether to surface', () => {
  assert.equal(evaluateSwiftBarBuild(null), null);
});
