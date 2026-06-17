#!/usr/bin/env node
// SessionStart hook：每天最多一次，在后台拉取+重建公司 MCP 仓(不阻塞会话)；
// 并把"团队插件有新版"提示带进会话上下文(插件更新是 slash，只能提示你点一下)。
// 关闭：环境变量 YOOONI_AUTOUPDATE=off ；立即触发一次：YOOONI_AUTOUPDATE=now
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');

const MODE = (process.env.YOOONI_AUTOUPDATE || 'on').toLowerCase();
let raw = '';
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', run);
process.stdin.on('error', run);

function run() {
  let out = '';
  try {
    if (MODE === 'off') return finish(out);
    const stateDir = path.join(os.homedir(), '.kai-toolbox');
    try { fs.mkdirSync(stateDir, { recursive: true }); } catch (e) {}
    const stamp = path.join(stateDir, 'team-tools-autoupdate.last');
    const notice = path.join(stateDir, 'team-tools-update.notice');

    // 浮现上一轮写下的"插件有新版"提示(无论是否到刷新时间)
    try { const n = fs.readFileSync(notice, 'utf8').trim(); if (n) out += n + '\n'; } catch (e) {}

    // 每日节流
    let last = 0;
    try { last = parseInt(fs.readFileSync(stamp, 'utf8'), 10) || 0; } catch (e) {}
    const due = MODE === 'now' || (Date.now() - last) >= 24 * 3600 * 1000;

    if (due && process.platform === 'win32') {
      try { fs.writeFileSync(stamp, String(Date.now())); } catch (e) {}
      const ps1 = path.join(__dirname, '..', 'scripts', 'update-team-tools.ps1');
      try {
        const child = spawn('powershell',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ps1],
          { detached: true, stdio: 'ignore', windowsHide: true });
        child.unref();
        out += '公司团队套件正在后台刷新(每日一次：MCP 仓 git pull + 必要时重建)。';
      } catch (e) {}
    }
  } catch (e) {}
  finish(out);
}

function finish(out) {
  if (out && out.trim()) process.stdout.write('[team-tools] ' + out.trim() + '\n');
  process.exit(0);
}
