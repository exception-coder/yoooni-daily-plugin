#!/usr/bin/env node
// UserPromptSubmit hook: detect a newer on-disk plugin and remind once per session.

const fs = require('fs');
const os = require('os');
const path = require('path');

const COMMON_OFF_ENV = 'TEAM_TOOLS_VERSION_REMINDER';
const LEGACY_OFF_ENV_BY_PLUGIN = Object.freeze({
  'team-standards': 'TEAM_STANDARDS_VERSION_REMINDER',
  'project-coding-profiles': 'PCP_VERSION_REMINDER',
  'yoooni-daily-plugin': 'YOOONI_VERSION_REMINDER',
});
function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (_) {
    return null;
  }
}

function loadedPlugin() {
  const root = process.env.CLAUDE_PLUGIN_ROOT;
  if (!root) return null;
  const manifest = readJson(path.join(root, '.claude-plugin', 'plugin.json'));
  if (!manifest || typeof manifest.name !== 'string' || typeof manifest.version !== 'string') return null;
  return { name: manifest.name, version: manifest.version };
}

function latestVersion(pluginName) {
  const manifestPath = path.join(
    os.homedir(),
    '.claude',
    'plugins',
    'marketplaces',
    pluginName,
    '.claude-plugin',
    'marketplace.json'
  );
  const marketplace = readJson(manifestPath);
  if (!marketplace || !Array.isArray(marketplace.plugins)) return null;
  const plugin = marketplace.plugins.find((entry) => entry && entry.name === pluginName);
  return plugin && typeof plugin.version === 'string' ? plugin.version : null;
}

function isReminderDisabled(pluginName) {
  if ((process.env[COMMON_OFF_ENV] || 'on').toLowerCase() === 'off') return true;
  const legacyEnv = LEGACY_OFF_ENV_BY_PLUGIN[pluginName];
  return Boolean(legacyEnv && (process.env[legacyEnv] || 'on').toLowerCase() === 'off');
}

function compareSemver(left, right) {
  const leftParts = String(left).split('.').map((part) => Number.parseInt(part, 10));
  const rightParts = String(right).split('.').map((part) => Number.parseInt(part, 10));
  for (let index = 0; index < Math.max(leftParts.length, rightParts.length); index += 1) {
    const leftValue = leftParts[index] || 0;
    const rightValue = rightParts[index] || 0;
    if (Number.isNaN(leftValue) || Number.isNaN(rightValue)) return 0;
    if (leftValue > rightValue) return 1;
    if (leftValue < rightValue) return -1;
  }
  return 0;
}

function claimReminder(session, tag) {
  try {
    const directory = path.join(os.homedir(), '.kai-toolbox');
    fs.mkdirSync(directory, { recursive: true });
    const flag = path.join(directory, `.restart-reminded-${session}`);
    const descriptor = fs.openSync(flag, 'wx');
    fs.writeSync(descriptor, tag);
    fs.closeSync(descriptor);
    return true;
  } catch (_) {
    return false;
  }
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  raw += chunk;
});
process.stdin.on('end', () => {
  try {
    const payload = JSON.parse(raw);
    const loaded = loadedPlugin();
    if (!loaded || isReminderDisabled(loaded.name)) process.exit(0);

    const latest = latestVersion(loaded.name);
    if (!latest || compareSemver(latest, loaded.version) <= 0) process.exit(0);

    const session = payload.session_id || 'nosession';
    if (!claimReminder(session, `${loaded.name}@${latest}`)) process.exit(0);

    const legacyEnv = LEGACY_OFF_ENV_BY_PLUGIN[loaded.name];
    const legacyHint = legacyEnv ? `（兼容 ${legacyEnv}=off）` : '';
    process.stderr.write(
      `[team-tools] 团队插件已更新（${loaded.name} ${loaded.version}→${latest}），当前会话仍在运行旧版。\n` +
      '  新内容 / 新 hook 不会在本会话生效——请重启 Claude Code 会话后再继续。\n' +
      `  旁路：${COMMON_OFF_ENV}=off ${legacyHint}\n`
    );
  } catch (_) {
    // Version reminders are best-effort and must never block prompt submission.
  }
  process.exit(0);
});
