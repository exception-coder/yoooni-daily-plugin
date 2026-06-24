#!/usr/bin/env node
// =============================================================
// 团队「疑问/纠正」信号汇总 —— 为 yoooni-hook-report 周报的「规整」环节备料。
//
// 读 \\IT01\版本更新\vibecoding\prompt-signals-*.jsonl（由 team-standards 的
// prompt-signal-capture hook 本地登记、update-team-tools.ps1 同步），
// 去噪 + 去重 + 按优先级排序，输出高价值条目（纠正/疑问/业务任务）。
//
// 本脚本只做【机械备料】，不做判定；真正的「精准提取业务缺口 → 该补什么」由
// SKILL 里的 LLM 规整完成（见 SKILL.md「② 疑问/纠正规整」）。
//
// 用法：node prompt-signal-report.mjs [shareDir] [--days=N] [--top=N] [--json]
//   shareDir  默认 \\IT01\版本更新\vibecoding
//   --days=N  最近 N 天（默认 7；0=全部）
//   --top=N   高价值条目上限（默认 60）
//   --json    输出原始 JSON（默认可读文本）
// =============================================================
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const shareDir = args.find((a) => !a.startsWith('--')) || '\\\\IT01\\版本更新\\vibecoding';
const days = (() => { const a = args.find((x) => x.startsWith('--days=')); return a ? parseInt(a.split('=')[1], 10) : 7; })();
const top = (() => { const a = args.find((x) => x.startsWith('--top=')); return a ? parseInt(a.split('=')[1], 10) : 60; })();
const asJson = args.includes('--json');

const PRIO = { 'high+': 0, high: 1, medium: 2, low: 3 };

function read(dir) {
  let files;
  try { files = fs.readdirSync(dir).filter((f) => /^prompt-signals-.*\.jsonl$/i.test(f)); }
  catch (e) {
    console.error(`[prompt-signal-report] 读不到目录: ${dir}\n  ${e.message}`);
    console.error('  确认能访问 \\\\IT01（否则先跑 yoooni-smb-share-access 修 SMB），或传本地目录参数。');
    process.exit(1);
  }
  const out = [];
  for (const f of files) {
    let t; try { t = fs.readFileSync(path.join(dir, f), 'utf8'); } catch (_) { continue; }
    for (const ln of t.split(/\r?\n/)) { const s = ln.trim(); if (!s) continue; try { out.push(JSON.parse(s)); } catch (_) { /* 跳过坏行 */ } }
  }
  return out;
}
function withinDays(ev, n) { if (!n || n <= 0) return true; const t = Date.parse(ev.ts); return Number.isNaN(t) ? true : (Date.now() - t) <= n * 86400000; }

let evs = read(shareDir).filter((e) => withinDays(e, days));
evs = evs.filter((e) => e && e.kind !== 'command' && (e.text || '').trim());   // 丢命令噪声(旧数据可能有)+空
const seen = new Set();                                                         // 同 project+text 去重(跨机/历史)
evs = evs.filter((e) => { const k = (e.project || '') + '' + (e.text || '').trim(); if (seen.has(k)) return false; seen.add(k); return true; });
evs.sort((a, b) => (PRIO[a.priority] ?? 9) - (PRIO[b.priority] ?? 9) || (Date.parse(b.ts) || 0) - (Date.parse(a.ts) || 0));

function tally(key) { const m = new Map(); for (const e of evs) { const k = e[key] ?? '(?)'; m.set(k, (m.get(k) || 0) + 1); } return [...m].sort((a, b) => b[1] - a[1]); }
const summary = { shareDir, days, total: evs.length, byKind: tally('kind'), byPriority: tally('priority'), byProject: tally('project') };
const items = evs.slice(0, top).map((e) => ({
  ts: (e.ts || '').slice(0, 10), user: e.user, project: e.project, kind: e.kind, priority: e.priority,
  afterEdit: !!e.afterEdit, text: (e.text || '').replace(/\s+/g, ' ').slice(0, 400),
}));

if (asJson) { console.log(JSON.stringify({ summary, items }, null, 2)); }
else {
  console.log('# 团队疑问/纠正信号（待 LLM 规整素材）');
  console.log(`源：${shareDir}　范围：最近 ${days || '全部'} 天　去噪去重后 ${summary.total} 条`);
  console.log('按类型：  ' + summary.byKind.map(([k, v]) => `${k}=${v}`).join('  '));
  console.log('按优先级：' + summary.byPriority.map(([k, v]) => `${k}=${v}`).join('  '));
  console.log('按项目：  ' + summary.byProject.map(([k, v]) => `${k}=${v}`).join('  '));
  console.log(`\n## 高价值条目（按 priority 排序，前 ${top} 条）`);
  if (items.length === 0) console.log('  (无数据)');
  for (const it of items) {
    console.log(`- [${it.priority}|${it.kind}${it.afterEdit ? '|afterEdit' : ''}] (${it.project}/${it.user}/${it.ts}) ${it.text}`);
  }
}
