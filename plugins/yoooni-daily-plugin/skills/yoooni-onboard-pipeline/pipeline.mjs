#!/usr/bin/env node
// =============================================================
// project-onboard-pipeline 编排脚本（机械胶水层）
//   把项目接入、画像、编码约束、实现图谱、领域知识、Core Spec、运行证据与拓扑
//   这条初始化流水线的【确定性步骤】串起来；【需判断的步骤】留给 skill 里的 AI + 人。
//
//   设计红线（与 domain-knowledge-bootstrap 同源）：
//     - 脚本只做机械活：clone/定位、探测分离、建聚合、生成阶段清单与状态。
//     - 不自动抽业务内容、不自动判模块/技术栈/stable —— 那些是 skill 关卡里人/AI 的事。
//     - 幂等：已存在的不重复 clone/聚合；可断点续跑。
//
// 子命令：
//   plan     --repos <url-or-path>... [--name <系统名>] [--ws <工作区父目录>]
//              探测每个仓(本地路径或待 clone)、推断前后端角色、产出阶段计划 JSON(打印+落状态文件)
//   clone    --repos <url>... --into <目录>        机械 clone(已存在跳过)
//   aggregate --name <系统名> --members <路径>...   调 taskspace 建聚合工作区(复用现有 skill 脚本)
//   status   --state <状态文件>                     看某次 onboard 的阶段进度
//
// 状态文件：默认 ~/.kai-toolbox/onboard-<系统名>.json，记录阶段生命周期与关卡待确认项。
// =============================================================

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';

const STATE_DIR = path.join(os.homedir(), '.kai-toolbox');
const TASKSPACE = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')),
  '..', 'yoooni-taskspace', 'taskspace.mjs');

const STATE_SCHEMA_VERSION = 2;
const STAGE_STATUSES = new Set(['pending', 'needs-review', 'waiting-evidence', 'done', 'skipped']);
const SKIPPABLE_STAGE_IDS = new Set(['aggregate', 'topology']);

// 流水线十阶段（与 SKILL.md 对齐）。保留原六个阶段 ID，兼容已有状态文件。
const STAGES = [
  { id: 'fetch',     name: '① 拉取/定位项目',          auto: 'full',  gate: '确认仓库地址、角色与系统边界' },
  { id: 'profile',   name: '② 项目画像 + Agent 入口',  auto: 'semi',  gate: '确认技术栈、分层、启动方式与编码' },
  { id: 'coding',    name: '③ 编码 profile',           auto: 'semi',  gate: '确认 rootMarkers 与编码/框架定性' },
  { id: 'aggregate', name: '④ 多仓聚合工作区',         auto: 'full',  gate: '确认成员完整；单仓项目可跳过' },
  { id: 'graphify',  name: '⑤ Graphify 实现事实图谱',  auto: 'semi',  gate: 'graph.json 存在且健康检查已记录' },
  { id: 'knowledge', name: '⑥ 领域知识与 DDL 基线',    auto: 'human', gate: '模块边界、路径与业务真理候选已确认' },
  { id: 'core-spec', name: '⑦ Core Spec 静态候选',     auto: 'semi',  gate: '全模块候选已生成，未经评审不升 stable' },
  { id: 'evidence',  name: '⑧ 运行证据与规格挖掘',     auto: 'semi',  gate: '证据可追溯；无数据时标记 waiting-evidence' },
  { id: 'topology',  name: '⑨ 跨项目拓扑登记',         auto: 'human', gate: '集成关系已登记；无跨项目调用可跳过' },
  { id: 'verify',    name: '⑩ 验证、评审与发布',       auto: 'human', gate: '必选阶段闭环，索引/MCP/交付报告已完成' },
];
const STAGE_IDS = new Set(STAGES.map((stage) => stage.id));

function parseArgs(argv) {
  const out = { _: [] };
  let key = null;
  for (const a of argv) {
    if (a.startsWith('--')) { key = a.slice(2); out[key] = out[key] || []; }
    else if (key) out[key].push(a);
    else out._.push(a);
  }
  // 单值便捷访问
  for (const k of Object.keys(out)) if (Array.isArray(out[k]) && out[k].length === 1) out[k + '$'] = out[k][0];
  return out;
}

function ensureStateDir() { try { fs.mkdirSync(STATE_DIR, { recursive: true }); } catch {} }
function statePath(name) { return path.join(STATE_DIR, `onboard-${name}.json`); }
function loadState(name) { try { return JSON.parse(fs.readFileSync(statePath(name), 'utf8')); } catch { return null; } }
function saveState(name, s) { ensureStateDir(); fs.writeFileSync(statePath(name), JSON.stringify(s, null, 2), 'utf8'); }

function syncStateStages(state) {
  state.schemaVersion = STATE_SCHEMA_VERSION;
  state.stages = state.stages || {};
  for (const stage of STAGES) {
    const current = state.stages[stage.id] || {};
    state.stages[stage.id] = {
      ...current,
      name: stage.name,
      auto: stage.auto,
      gate: stage.gate,
      status: current.status || 'pending',
    };
  }
  return state;
}

function validateStageStatus(status) {
  if (!STAGE_STATUSES.has(status)) {
    die(`未知状态 ${status}；允许值：${[...STAGE_STATUSES].join(', ')}`);
  }
}

function validateStageTransition(state, stage, status) {
  if (status === 'skipped' && !SKIPPABLE_STAGE_IDS.has(stage)) {
    die(`阶段 ${stage} 不允许 skipped；只有 aggregate 和 topology 可跳过`);
  }
  if (stage !== 'verify' || status !== 'done') return;
  const blockers = STAGES
    .filter((candidate) => candidate.id !== 'verify')
    .filter((candidate) => !['done', 'skipped'].includes(state.stages[candidate.id].status))
    .map((candidate) => `${candidate.id}:${state.stages[candidate.id].status}`);
  if (blockers.length) die(`verify 不能完成；仍有未闭环阶段：${blockers.join(', ')}`);
}

// PLACEHOLDER_CMDS

// 探测一个仓(本地路径)的角色线索：后端/前端/微服务
function probeRepo(p) {
  const r = { path: p, exists: fs.existsSync(p), role: 'unknown', stack: [], encoding: 'unknown' };
  if (!r.exists) return r;
  const has = (f) => fs.existsSync(path.join(p, f));
  // 前端
  if (has('package.json')) {
    r.role = 'frontend';
    try {
      const pkg = JSON.parse(fs.readFileSync(path.join(p, 'package.json'), 'utf8'));
      const dep = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };
      if (dep.vue) r.stack.push('vue' + (dep.vue.includes('2') ? '2' : dep.vue.includes('3') ? '3' : ''));
      if (dep.react) r.stack.push('react');
      if (dep['element-ui']) r.stack.push('element-ui');
      if (dep.vite) r.stack.push('vite'); else if (dep['@vue/cli-service']) r.stack.push('vue-cli');
      r.encoding = 'utf-8';
    } catch {}
  }
  // 后端 Java：Maven/Gradle，或传统 Eclipse/IDEA 工程(.classpath/.iml)，或 src 下有 .java
  const isMvnGradle = has('pom.xml') || has('build.gradle');
  const isLegacyJava = has('.classpath') || fs.readdirSync(p).some((f) => f.endsWith('.iml'));
  let hasJavaSrc = false;
  try { hasJavaSrc = fs.existsSync(path.join(p, 'src')) && walkHasExt(path.join(p, 'src'), '.java', 3); } catch {}
  if (isMvnGradle || isLegacyJava || hasJavaSrc) {
    r.role = r.role === 'frontend' ? 'fullstack-mono' : 'backend';
    if (has('pom.xml')) r.stack.push('maven');
    else if (has('build.gradle')) r.stack.push('gradle');
    else if (isLegacyJava) r.stack.push('java-legacy');
    // 微服务多模块线索
    try {
      const subPoms = fs.readdirSync(p, { withFileTypes: true })
        .filter((d) => d.isDirectory() && fs.existsSync(path.join(p, d.name, 'pom.xml'))).length;
      if (subPoms >= 2) r.stack.push('multi-module');
    } catch {}
    // 编码:GBK 老项目由 skill 阶段②用 encoding-guard 精确探测;这里仅给初值
    r.encoding = isMvnGradle ? 'utf-8' : 'unknown(可能GBK,阶段②探测)';
  }
  if (r.role === 'unknown' && has('.gitignore')) r.role = 'docs-or-other';
  return r;
}

// 浅层(限定深度)判断目录下是否有某扩展名文件，避免遍历整个大仓
function walkHasExt(dir, ext, depth) {
  if (depth < 0) return false;
  let es; try { es = fs.readdirSync(dir, { withFileTypes: true }); } catch { return false; }
  for (const e of es) {
    if (e.isFile() && e.name.endsWith(ext)) return true;
  }
  for (const e of es) {
    if (e.isDirectory() && walkHasExt(path.join(dir, e.name), ext, depth - 1)) return true;
  }
  return false;
}

function cmdPlan(a) {
  const repos = a.repos || [];
  if (!repos.length) die('plan 需要 --repos <本地路径或 git url>...');
  const name = a['name$'] || path.basename(repos[0]).replace(/\.git$/, '');
  const probes = repos.map((rp) => {
    // 本地路径直接探测；url 形态记为待 clone
    if (/^https?:|^git@/.test(rp)) return { path: rp, exists: false, role: 'to-clone', stack: [], encoding: 'unknown' };
    return probeRepo(path.resolve(rp));
  });
  const separated = probes.filter((x) => x.role === 'frontend').length && probes.filter((x) => x.role === 'backend').length;
  const state = syncStateStages(loadState(name) || {
    system: name,
    createdAt: new Date().toISOString(),
    repos: [],
    stages: {},
  });
  state.repos = probes;
  state.separated = !!separated;
  state.updatedAt = new Date().toISOString();
  saveState(name, state);

  console.log(`# Onboard 计划：${name}`);
  console.log(`系统类型：${separated ? '前后端分离' : (probes.length > 1 ? '多仓' : '单仓')}\n`);
  console.log('## 仓库探测');
  for (const p of probes) {
    console.log(`- ${p.path}`);
    console.log(`    角色:${p.role}  栈:${p.stack.join('/') || '?'}  编码:${p.encoding}  存在:${p.exists}`);
  }
  console.log('\n## 阶段计划（auto=full 自动 / semi=AI起草+人确认 / human=人判定）');
  for (const s of STAGES) console.log(`- ${s.name}  [${s.auto}]  关卡:${s.gate}`);
  console.log(`\n状态文件:${statePath(name)}`);
  console.log('下一步:skill 据此逐阶段推进,每阶段过关卡后调 pipeline.mjs mark 标记完成。');
}

function cmdMark(a) {
  const name = a['name$']; const stage = a['stage$']; const status = a['status$'] || 'done';
  if (!name || !stage) {
    die('mark 需要 --name <系统> --stage <阶段id> [--status pending|needs-review|waiting-evidence|done|skipped]');
  }
  if (!STAGE_IDS.has(stage)) die('未知阶段 ' + stage);
  validateStageStatus(status);
  const loaded = loadState(name) || die('找不到状态文件,先跑 plan');
  const state = syncStateStages(loaded);
  validateStageTransition(state, stage, status);
  state.stages[stage].status = status;
  state.stages[stage].at = new Date().toISOString();
  state.updatedAt = new Date().toISOString();
  saveState(name, state);
  console.log(`✓ ${name} / ${stage} → ${status}`);
}

function cmdAggregate(a) {
  const name = a['name$']; const members = a.members || [];
  if (!name || members.length < 2) die('aggregate 需要 --name <系统> --members <路径> <路径>...');
  const wsBase = a['ws$'] || path.join(os.homedir(), 'myWork');
  console.log(`调用 taskspace 创建聚合工作区 ${name}...`);
  try {
    execFileSync('node', [TASKSPACE, 'create', '--base', wsBase, '--name', name, '--members', ...members],
      { stdio: 'inherit' });
  } catch (e) { die('taskspace 调用失败:' + e.message); }
}

function cmdStatus(a) {
  const name = a['name$'] || a._[0];
  if (!name) die('status 需要 --name <系统>');
  const loaded = loadState(name) || die('找不到状态文件');
  const state = syncStateStages(loaded);
  console.log(`# Onboard 状态：${state.system}（前后端分离:${state.separated}）`);
  for (const s of STAGES) {
    const st = state.stages[s.id] || {};
    const mark = st.status === 'done' ? '✓'
      : st.status === 'skipped' ? '—'
        : st.status === 'needs-review' ? '?'
          : st.status === 'waiting-evidence' ? '~'
            : '·';
    console.log(`${mark} ${s.name}  [${st.status || 'pending'}]`);
  }
  const next = STAGES.find((stage) => !['done', 'skipped'].includes(state.stages[stage.id].status));
  console.log(next ? `下一待办：${next.id} — ${next.gate}` : '全部阶段已闭环。');
}

const a = parseArgs(process.argv.slice(2));
switch (a._[0]) {
  case 'plan': cmdPlan(a); break;
  case 'mark': cmdMark(a); break;
  case 'aggregate': cmdAggregate(a); break;
  case 'status': cmdStatus(a); break;
  default:
    console.log(`project-onboard-pipeline 编排脚本

用法:
  node pipeline.mjs plan --repos <路径或url>... [--name <系统名>] [--ws <工作区父目录>]
  node pipeline.mjs mark --name <系统> --stage <fetch|profile|coding|aggregate|graphify|knowledge|core-spec|evidence|topology|verify>
    [--status pending|needs-review|waiting-evidence|done|skipped]
  node pipeline.mjs aggregate --name <系统> --members <路径>...
  node pipeline.mjs status --name <系统>`);
}

function die(m) { console.error('✗ ' + m); process.exit(1); }
