import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const testsDirectory = path.dirname(fileURLToPath(import.meta.url));
const pluginRoot = path.resolve(testsDirectory, '..', '..');
const reportScript = path.join(pluginRoot, 'skills', 'yoooni-hook-report', 'hook-report.mjs');

function event(overrides = {}) {
  return {
    schemaVersion: 1,
    ts: new Date().toISOString(),
    user: 'tester',
    host: 'test-host',
    plugin: 'team-standards',
    hook: 'check-example',
    rule: 'example',
    mode: 'warn',
    tool: 'Edit',
    file: 'C:\\workspace\\Example.js',
    ...overrides,
  };
}

test('hook report accepts v1 and legacy records while exposing invalid rows', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hook-report-v1-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));

  const legacy = event();
  delete legacy.schemaVersion;
  const lines = [
    JSON.stringify(event()),
    JSON.stringify(legacy),
    JSON.stringify(event({ schemaVersion: 2 })),
    JSON.stringify(event({ mode: 'observe' })),
    '{broken-json',
  ];
  fs.writeFileSync(path.join(directory, 'hook-events-test.jsonl'), `${lines.join('\n')}\n`, 'utf8');

  const result = spawnSync(process.execPath, [reportScript, directory, '--days=0', '--json'], {
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.equal(report.total, 2);
  assert.equal(report.totalAll, 2);
  assert.equal(report.legacyRecords, 1);
  assert.equal(report.invalidRecords, 3);
});
