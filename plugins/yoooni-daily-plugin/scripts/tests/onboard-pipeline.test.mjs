import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const PIPELINE = fileURLToPath(new URL('../../skills/yoooni-onboard-pipeline/pipeline.mjs', import.meta.url));
const STAGE_IDS = [
  'fetch',
  'profile',
  'coding',
  'aggregate',
  'graphify',
  'knowledge',
  'core-spec',
  'evidence',
  'topology',
  'verify',
];

function createTestHome(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'onboard-pipeline-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  return home;
}

function runPipeline(home, args) {
  return spawnSync(process.execPath, [PIPELINE, ...args], {
    encoding: 'utf8',
    env: { ...process.env, HOME: home, USERPROFILE: home },
  });
}

function statePath(home, name) {
  return path.join(home, '.kai-toolbox', `onboard-${name}.json`);
}

test('plan creates the ten-stage onboarding state', (t) => {
  const home = createTestHome(t);
  const frontend = path.join(home, 'frontend');
  const backend = path.join(home, 'backend');
  fs.mkdirSync(frontend);
  fs.mkdirSync(backend);
  fs.writeFileSync(path.join(frontend, 'package.json'), JSON.stringify({ dependencies: { vue: '^3.0.0' } }));
  fs.writeFileSync(path.join(backend, 'pom.xml'), '<project/>');

  const result = runPipeline(home, ['plan', '--repos', frontend, backend, '--name', 'demo']);

  assert.equal(result.status, 0, result.stderr);
  const state = JSON.parse(fs.readFileSync(statePath(home, 'demo'), 'utf8'));
  assert.equal(state.schemaVersion, 2);
  assert.equal(state.separated, true);
  assert.deepEqual(Object.keys(state.stages), STAGE_IDS);
  assert.equal(state.stages.graphify.status, 'pending');
  assert.equal(state.stages['core-spec'].status, 'pending');
  assert.match(result.stdout, /Graphify 实现事实图谱/);
  assert.match(result.stdout, /运行证据与规格挖掘/);
});

test('mark migrates a legacy state and preserves completed stages', (t) => {
  const home = createTestHome(t);
  const stateDir = path.join(home, '.kai-toolbox');
  fs.mkdirSync(stateDir);
  fs.writeFileSync(statePath(home, 'legacy'), JSON.stringify({
    system: 'legacy',
    createdAt: '2026-01-01T00:00:00.000Z',
    repos: [],
    stages: {
      fetch: { name: '旧名称', status: 'done', at: '2026-01-02T00:00:00.000Z' },
      knowledge: { name: '旧知识阶段', status: 'skipped', at: '2026-01-03T00:00:00.000Z' },
    },
  }, null, 2));

  const graphify = runPipeline(home, ['mark', '--name', 'legacy', '--stage', 'graphify', '--status', 'done']);
  const evidence = runPipeline(home, [
    'mark', '--name', 'legacy', '--stage', 'evidence', '--status', 'waiting-evidence',
  ]);
  const coreSpec = runPipeline(home, [
    'mark', '--name', 'legacy', '--stage', 'core-spec', '--status', 'needs-review',
  ]);

  assert.equal(graphify.status, 0, graphify.stderr);
  assert.equal(evidence.status, 0, evidence.stderr);
  assert.equal(coreSpec.status, 0, coreSpec.stderr);
  const state = JSON.parse(fs.readFileSync(statePath(home, 'legacy'), 'utf8'));
  assert.equal(state.schemaVersion, 2);
  assert.equal(state.stages.fetch.status, 'done');
  assert.equal(state.stages.fetch.at, '2026-01-02T00:00:00.000Z');
  assert.match(state.stages.fetch.name, /拉取\/定位项目/);
  assert.equal(state.stages.knowledge.status, 'skipped');
  assert.equal(state.stages.graphify.status, 'done');
  assert.equal(state.stages.evidence.status, 'waiting-evidence');
  assert.equal(state.stages['core-spec'].status, 'needs-review');
});

test('mark rejects unknown stages and lifecycle statuses without changing state', (t) => {
  const home = createTestHome(t);
  const planned = runPipeline(home, ['plan', '--repos', home, '--name', 'guarded']);
  assert.equal(planned.status, 0, planned.stderr);
  const before = fs.readFileSync(statePath(home, 'guarded'), 'utf8');

  const badStage = runPipeline(home, ['mark', '--name', 'guarded', '--stage', 'unknown', '--status', 'done']);
  const badStatus = runPipeline(home, ['mark', '--name', 'guarded', '--stage', 'evidence', '--status', 'complete']);
  const badSkip = runPipeline(home, ['mark', '--name', 'guarded', '--stage', 'evidence', '--status', 'skipped']);

  assert.notEqual(badStage.status, 0);
  assert.match(badStage.stderr, /未知阶段/);
  assert.notEqual(badStatus.status, 0);
  assert.match(badStatus.stderr, /未知状态/);
  assert.notEqual(badSkip.status, 0);
  assert.match(badSkip.stderr, /不允许 skipped/);
  assert.equal(fs.readFileSync(statePath(home, 'guarded'), 'utf8'), before);
});

test('status exposes review and evidence gaps as the next unfinished work', (t) => {
  const home = createTestHome(t);
  runPipeline(home, ['plan', '--repos', home, '--name', 'visible']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'fetch', '--status', 'done']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'profile', '--status', 'done']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'coding', '--status', 'done']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'aggregate', '--status', 'skipped']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'graphify', '--status', 'done']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'knowledge', '--status', 'done']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'core-spec', '--status', 'needs-review']);
  runPipeline(home, ['mark', '--name', 'visible', '--stage', 'evidence', '--status', 'waiting-evidence']);

  const result = runPipeline(home, ['status', '--name', 'visible']);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Core Spec 静态候选\s+\[needs-review\]/);
  assert.match(result.stdout, /运行证据与规格挖掘\s+\[waiting-evidence\]/);
  assert.match(result.stdout, /下一待办：core-spec/);
});

test('verify cannot complete until every preceding gate is closed', (t) => {
  const home = createTestHome(t);
  runPipeline(home, ['plan', '--repos', home, '--name', 'verified']);

  const premature = runPipeline(home, ['mark', '--name', 'verified', '--stage', 'verify', '--status', 'done']);
  assert.notEqual(premature.status, 0);
  assert.match(premature.stderr, /仍有未闭环阶段/);

  const file = statePath(home, 'verified');
  const state = JSON.parse(fs.readFileSync(file, 'utf8'));
  for (const stageId of STAGE_IDS) state.stages[stageId].status = 'done';
  state.stages.aggregate.status = 'skipped';
  state.stages.topology.status = 'skipped';
  state.stages.verify.status = 'pending';
  fs.writeFileSync(file, JSON.stringify(state, null, 2));

  const completed = runPipeline(home, ['mark', '--name', 'verified', '--stage', 'verify', '--status', 'done']);
  assert.equal(completed.status, 0, completed.stderr);
  const finalState = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(finalState.stages.verify.status, 'done');
});
