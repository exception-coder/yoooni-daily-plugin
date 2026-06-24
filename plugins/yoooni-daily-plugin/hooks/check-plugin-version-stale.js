#!/usr/bin/env node
// =============================================================
// UserPromptSubmit hook: 团队插件版本陈旧 → 提醒重启会话
//
// 背景：Claude Code 在【会话启动那一刻】把 plugins/hooks/skills 一次性
// 加载进内存，运行中不热加载。每日刷新 / 计划任务会把新版插件拉到磁盘，
// 但同事若一直泡在老会话里不重启，这个会话就一直跑旧版——新脚本、新 hook
// 全都不生效。本 hook 在每条 prompt 提交时比对：
//   已加载版本（当前会话运行的 ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json）
//   vs 磁盘最新版本（marketplace 克隆的 .claude-plugin/marketplace.json）
// 后者更高 → stderr 提醒「插件已更新，请重启会话」。
//
// 最佳实践（各自检测 + 共享去重）：
//   - 「已加载版本」只能靠各插件自己的 CLAUDE_PLUGIN_ROOT 拿到，跨插件拿不到，
//     故三个团队插件各放一份本 hook、只判自己（MARKETPLACE/PLUGIN 常量区分）。
//   - 三个插件同日一起更新时不刷三条：用会话级共享 flag
//     ~/.kai-toolbox/.restart-reminded-<session> 原子抢占，谁先抢到谁提醒一次，
//     其余静默——反正重启一次三个插件全更新。
//
// 红线（与本插件其它 hook 同源）：
//   - best-effort：任何读取失败一律静默 exit 0，绝不影响 prompt 放行。
//   - 绝不写 stdout（UserPromptSubmit 的 stdout 会注入 prompt），只写 stderr。
//   - 绝不 exit 非 0（不拦截输入）。
//
// 已知局限（鸡生蛋）：本 hook 自身也要会话重启后才生效，故只对「装上本 hook
//   之后的版本更新」起作用——越早铺开越省心。
// 旁路：YOOONI_VERSION_REMINDER=off 关闭。
// =============================================================

const fs = require('fs');
const os = require('os');
const path = require('path');

// —— 每个插件复制本文件时，只改这三行 ——
const MARKETPLACE = 'yoooni-daily-plugin'; // 本插件所在 marketplace 名
const PLUGIN = 'yoooni-daily-plugin';      // 本插件名（marketplace.json plugins[].name）
const OFF_ENV = 'YOOONI_VERSION_REMINDER';        // 关闭开关环境变量名

if ((process.env[OFF_ENV] || 'on').toLowerCase() === 'off') process.exit(0);

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return null; }
}

// 已加载版本：当前会话运行目录的 plugin.json
function loadedVersion() {
  const root = process.env.CLAUDE_PLUGIN_ROOT;
  if (!root) return null;
  const j = readJson(path.join(root, '.claude-plugin', 'plugin.json'));
  return j && typeof j.version === 'string' ? j.version : null;
}

// 磁盘最新版本：marketplace 克隆里的 marketplace.json
function latestVersion() {
  const mp = path.join(os.homedir(), '.claude', 'plugins', 'marketplaces', MARKETPLACE, '.claude-plugin', 'marketplace.json');
  const j = readJson(mp);
  if (!j || !Array.isArray(j.plugins)) return null;
  const e = j.plugins.find((x) => x && x.name === PLUGIN);
  return e && typeof e.version === 'string' ? e.version : null;
}

// 1 if a>b, -1 if a<b, 0 if 相等/解析失败（保守不提醒）
function cmpSemver(a, b) {
  const pa = String(a).split('.').map((n) => parseInt(n, 10));
  const pb = String(b).split('.').map((n) => parseInt(n, 10));
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (Number.isNaN(x) || Number.isNaN(y)) return 0;
    if (x > y) return 1;
    if (x < y) return -1;
  }
  return 0;
}

// 会话级共享去重：原子创建 flag，抢到返回 true（由我提醒一次），已存在/失败返回 false。
// 用 'wx' 保证多个插件 hook 并发时只有一个胜出，杜绝同一 prompt 弹多条。
function claimReminder(session, tag) {
  try {
    const dir = path.join(os.homedir(), '.kai-toolbox');
    fs.mkdirSync(dir, { recursive: true });
    const flag = path.join(dir, `.restart-reminded-${session}`);
    const fd = fs.openSync(flag, 'wx'); // 已存在则抛 EEXIST
    fs.writeSync(fd, tag);
    fs.closeSync(fd);
    return true;
  } catch (_) {
    return false; // 已有人提醒过 / 写失败 → 静默
  }
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  try {
    const payload = JSON.parse(raw);
    const loaded = loadedVersion();
    const latest = latestVersion();
    if (!loaded || !latest) process.exit(0);
    if (cmpSemver(latest, loaded) <= 0) process.exit(0); // 磁盘不比当前新 → 不提醒

    const session = payload.session_id || 'nosession';
    if (!claimReminder(session, `${PLUGIN}@${latest}`)) process.exit(0);

    process.stderr.write(
      `[team-tools] 团队插件已更新（${PLUGIN} ${loaded}→${latest}），当前会话仍在运行旧版。\n` +
      `  新脚本 / 新 hook 不会在本会话生效——请重启 Claude Code 会话（开新会话）后再继续。\n` +
      `  旁路：${OFF_ENV}=off 关闭本提醒。\n`
    );
  } catch (_) {
    // 静默：提醒是附带能力，任何失败都不得影响 prompt 放行
  }
  process.exit(0);
});
