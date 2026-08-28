#!/usr/bin/env node
// =============================================================
// hook 命中周报：读取公司共享里各人的 hook 命中事件，聚合出统计。
//
// 数据来源：\\IT01\版本更新\vibecoding\hook-events-<用户>-<机器>.jsonl
//   每行一条 {ts,user,host,plugin,hook,rule,mode,tool,file}，
//   由 team-standards / project-coding-profiles 的 warn hook 本地写入、
//   再由 update-team-tools.ps1 best-effort 同步到该共享（每人一文件）。
//
// 用法：
//   node hook-report.mjs [shareDir] [--days=N] [--json]
//     shareDir  共享目录，默认 \\IT01\版本更新\vibecoding
//     --days=N  只统计最近 N 天（默认 7；0=全部）
//     --json    输出原始聚合 JSON（默认输出可读文本表）
// =============================================================

import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const shareDir = (args.find((a) => !a.startsWith('--'))) || '\\\\IT01\\版本更新\\vibecoding';
const daysArg = args.find((a) => a.startsWith('--days='));
const days = daysArg ? parseInt(daysArg.split('=')[1], 10) : 7;
const asJson = args.includes('--json');
const REQUIRED_STRING_FIELDS = ['user', 'host', 'plugin', 'hook', 'rule', 'tool', 'file'];
const VALID_MODES = new Set(['warn', 'block']);

function normalizeHookEvent(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const legacy = value.schemaVersion === undefined;
  if (!legacy && value.schemaVersion !== 1) return null;
  if (typeof value.ts !== 'string' || Number.isNaN(Date.parse(value.ts))) return null;
  if (!VALID_MODES.has(value.mode)) return null;
  for (const field of REQUIRED_STRING_FIELDS) {
    if (typeof value[field] !== 'string' || value[field].trim() === '') return null;
  }
  return {
    event: {
      schemaVersion: 1,
      ts: value.ts,
      user: value.user.trim(),
      host: value.host.trim(),
      plugin: value.plugin.trim(),
      hook: value.hook.trim(),
      rule: value.rule.trim(),
      mode: value.mode,
      tool: value.tool.trim(),
      file: value.file.trim(),
    },
    legacy,
  };
}

function readEvents(dir) {
  let files;
  try {
    files = fs.readdirSync(dir).filter((f) => /^hook-events-.*\.jsonl$/i.test(f));
  } catch (e) {
    console.error(`[hook-report] 读不到共享目录: ${dir}\n  ${e.message}`);
    console.error('  确认能访问 \\\\IT01（必要时先跑 yoooni-smb-share-access 修 SMB），或传入本地目录参数。');
    process.exit(1);
  }
  const events = [];
  let invalidRecords = 0;
  let legacyRecords = 0;
  for (const f of files) {
    let text;
    try { text = fs.readFileSync(path.join(dir, f), 'utf8'); } catch (_) { continue; }
    for (const line of text.split(/\r?\n/)) {
      const s = line.trim();
      if (!s) continue;
      try {
        const normalized = normalizeHookEvent(JSON.parse(s));
        if (!normalized) {
          invalidRecords += 1;
          continue;
        }
        if (normalized.legacy) legacyRecords += 1;
        events.push(normalized.event);
      } catch (_) {
        invalidRecords += 1;
      }
    }
  }
  return { events, invalidRecords, legacyRecords };
}

function withinDays(ev, n) {
  if (!n || n <= 0) return true;
  const t = Date.parse(ev.ts);
  if (Number.isNaN(t)) return true;
  return (Date.now() - t) <= n * 86400000;
}

function tally(events, key) {
  const m = new Map();
  for (const ev of events) {
    const k = ev[key] ?? '(unknown)';
    m.set(k, (m.get(k) || 0) + 1);
  }
  return [...m.entries()].sort((a, b) => b[1] - a[1]);
}

function printTable(title, rows, colName) {
  console.log(`\n## ${title}`);
  if (rows.length === 0) { console.log('  (无数据)'); return; }
  const w = Math.max(colName.length, ...rows.map(([k]) => String(k).length));
  console.log(`  ${colName.padEnd(w)}  次数`);
  console.log(`  ${'-'.repeat(w)}  ----`);
  for (const [k, v] of rows) console.log(`  ${String(k).padEnd(w)}  ${v}`);
}

const readResult = readEvents(shareDir);
const all = readResult.events;
const events = all.filter((e) => withinDays(e, days));

const agg = {
  shareDir,
  days,
  totalAll: all.length,
  total: events.length,
  invalidRecords: readResult.invalidRecords,
  legacyRecords: readResult.legacyRecords,
  byRule: tally(events, 'rule'),
  byUser: tally(events, 'user'),
  byMode: tally(events, 'mode'),
  byHook: tally(events, 'hook'),
  byPlugin: tally(events, 'plugin'),
};

if (asJson) {
  console.log(JSON.stringify(agg, null, 2));
} else {
  console.log(`# hook 命中周报`);
  console.log(`数据源：${shareDir}`);
  console.log(`范围：最近 ${days || '全部'} 天　|　事件数：${agg.total}（全量 ${agg.totalAll}）`);
  console.log(`契约：legacy v1 ${agg.legacyRecords} 条　|　跳过无效记录 ${agg.invalidRecords} 条`);
  printTable('规则命中 Top（决定升不升 block 的依据）', agg.byRule, '规则');
  printTable('谁命中最多（谁常踩规范）', agg.byUser, '用户');
  printTable('warn vs block', agg.byMode, '模式');
  printTable('按 hook', agg.byHook, 'hook');
  printTable('按插件', agg.byPlugin, '插件');
  console.log('');
}
