#!/usr/bin/env node
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const PLUGIN = 'yoooni-daily-plugin';
const BASE = value('--base') || 'HEAD^';
const TARGET = value('--target');
const manifests = [`plugins/${PLUGIN}/.claude-plugin/plugin.json`, `plugins/${PLUGIN}/.codex-plugin/plugin.json`, '.claude-plugin/marketplace.json'];
const changed = git(['diff', '--name-only', BASE, ...(TARGET ? [TARGET] : [])]).split(/\r?\n/).filter(Boolean).filter(runtime);
if (!changed.length) { console.log('[version-bump] no plugin runtime payload changes'); process.exit(0); }
const versions = manifests.map((file, i) => { const data = JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8')); return i === 2 ? data.plugins[0].version : data.version; });
if (new Set(versions).size !== 1) fail(`manifest versions differ: ${versions.join(', ')}`);
const previous = JSON.parse(git(['show', `${BASE}:${manifests[0]}`])).version;
if (!greater(versions[0], previous)) fail(`runtime payload changed but version did not increase (${previous} -> ${versions[0]})`);
console.log(`[version-bump] OK ${previous} -> ${versions[0]}; runtime files: ${changed.length}`);
function runtime(file) { const prefix = `plugins/${PLUGIN}/`; if (!file.startsWith(prefix)) return false; const relative = file.slice(prefix.length); if (/^\.(?:claude|codex)-plugin\/plugin\.json$/.test(relative) || /^(?:hooks\/tests|hooks\/benchmarks)\//.test(relative) || relative === 'hooks/package.json') return false; return /^(?:skills|hooks|commands|agents|apps|mcp|scripts)\//.test(relative); }
function greater(a, b) { const x = semver(a); const y = semver(b); for (let i = 0; i < 3; i += 1) { if (x[i] !== y[i]) return x[i] > y[i]; } return false; }
function semver(v) { const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(v); if (!m) fail(`invalid SemVer: ${v}`); return m.slice(1).map(Number); }
function value(flag) { const i = process.argv.indexOf(flag); return i < 0 ? '' : process.argv[i + 1]; }
function git(args) { try { return execFileSync('git', ['-C', ROOT, ...args], { encoding: 'utf8' }).trim(); } catch (e) { fail(`cannot inspect baseline ${BASE}: ${e.message}`); } }
function fail(message) { console.error(`[version-bump] ${message}`); process.exit(1); }
