#!/usr/bin/env node
// SessionStart hook：每天最多一次，在后台刷新公司套件(不阻塞会话)；并把上轮"插件已更新"提示带进上下文。
// 跨平台：Windows 经 run-hidden.vbs 隐藏窗口跑 update-team-tools.ps1；macOS/Linux 后台 detached 跑 update-team-tools.sh。
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

    if (due) {
      const scripts = path.join(__dirname, '..', 'scripts');
      if (process.platform === 'win32') {
        try { fs.writeFileSync(stamp, String(Date.now())); } catch (e) {}
        const ps1 = path.join(scripts, 'update-team-tools.ps1');
        const vbs = path.join(scripts, 'run-hidden.vbs');
        try {
          // 经 VBS 以隐藏窗口(SW_HIDE)启动：powershell 及其子进程(git/npm/claude)全程无窗口、不闪黑框
          // （-WindowStyle Hidden 是"先开窗再藏"，挡不住那一瞬，故弃用）。
          const child = spawn('wscript.exe', [vbs, ps1],
            { detached: true, stdio: 'ignore', windowsHide: true });
          child.unref();
          out += '公司团队套件正在后台刷新(每日一次：MCP 仓 git pull + 插件 update)。';
        } catch (e) {}
      } else if (process.platform === 'darwin' || process.platform === 'linux') {
        // macOS / Linux：后台 detached 跑 bash 版（无窗口概念，直接 detach + 丢弃输出）。
        try { fs.writeFileSync(stamp, String(Date.now())); } catch (e) {}
        const sh = path.join(scripts, 'update-team-tools.sh');
        try {
          const child = spawn('bash', [sh],
            { detached: true, stdio: 'ignore' });
          child.unref();
          out += '公司团队套件正在后台刷新(每日一次：MCP 仓 git pull + 插件 update)。';
        } catch (e) {}
      }
    }
  } catch (e) {}
  finish(out);
}

function finish(out) {
  if (out && out.trim()) process.stdout.write('[team-tools] ' + out.trim() + '\n');
  process.exit(0);
}
