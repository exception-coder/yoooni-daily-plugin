#!/usr/bin/env node
// taskspace —— 跨平台「合并工作区」工具
// 在某个父目录下创建一个工作区目录，内部用软链接聚合若干项目。
// Windows 用 junction（无需管理员权限），macOS/Linux 用目录 symlink。
//
// 用法：
//   node taskspace.mjs create [--base <父目录>] [--name <工作区名>] [--members <p1> <p2> ...]
//   node taskspace.mjs create --pick <父目录>      # 交互式：列出子目录，输入序号多选
//   node taskspace.mjs list   <工作区目录>
//   node taskspace.mjs add    <工作区目录> <项目路径...>
//   node taskspace.mjs remove <工作区目录> <链接名...>
//   node taskspace.mjs teardown <工作区目录>       # 只删链接与清单，绝不动源项目

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';

const MANIFEST = '.taskspace.json';
const isWin = process.platform === 'win32';

function die(msg) {
  console.error('✗ ' + msg);
  process.exit(1);
}

function assertDir(p, label) {
  let st;
  try { st = fs.statSync(p); } catch { die(`${label}不存在: ${p}`); }
  if (!st.isDirectory()) die(`${label}不是目录: ${p}`);
}

// 是否为「链接」(symlink 或 Windows junction)。junction 在 lstat 下 isSymbolicLink()===true。
function isLink(p) {
  try { return fs.lstatSync(p).isSymbolicLink(); }
  catch { return false; }
}

// 安全删除一个链接：只删链接本身，绝不递归删除目标内容。
function removeLink(linkPath) {
  if (!isLink(linkPath)) {
    return { ok: false, reason: '不是链接，已跳过(保护源目录)' };
  }
  try {
    // 目录链接：mac/linux 用 unlink，win junction 用 rmdir。
    if (isWin) fs.rmdirSync(linkPath);
    else fs.unlinkSync(linkPath);
    return { ok: true };
  } catch (e) {
    // 兜底：rmSync 对链接只删链接本身，不删目标。
    try { fs.rmSync(linkPath, { recursive: false, force: false }); return { ok: true }; }
    catch (e2) { return { ok: false, reason: e2.message }; }
  }
}

function createLink(target, linkPath) {
  // type: 'junction' 在 Windows 生效(免管理员)，其它平台被忽略 → 普通目录 symlink。
  fs.symlinkSync(path.resolve(target), linkPath, 'junction');
}

function readManifest(wsDir) {
  const f = path.join(wsDir, MANIFEST);
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); }
  catch { return null; }
}

function writeManifest(wsDir, data) {
  fs.writeFileSync(path.join(wsDir, MANIFEST), JSON.stringify(data, null, 2) + '\n', 'utf8');
}

function uniqueLinkName(wsDir, base) {
  let name = base, i = 2;
  while (fs.existsSync(path.join(wsDir, name))) name = `${base}_${i++}`;
  return name;
}

function linkMembers(wsDir, members) {
  const added = [];
  for (const m of members) {
    const abs = path.resolve(m);
    assertDir(abs, '项目目录');
    const linkName = uniqueLinkName(wsDir, path.basename(abs));
    createLink(abs, path.join(wsDir, linkName));
    added.push({ link: linkName, target: abs });
    console.log(`  + ${linkName}  →  ${abs}`);
  }
  return added;
}

function ask(rl, q) {
  return new Promise((res) => rl.question(q, (a) => res(a.trim())));
}

async function pickSubdirs(parent) {
  assertDir(parent, '父目录');
  const subs = fs.readdirSync(parent, { withFileTypes: true })
    .filter((d) => d.isDirectory() || d.isSymbolicLink())
    .map((d) => d.name)
    .sort();
  if (!subs.length) die(`${parent} 下没有子目录`);
  console.log(`\n${parent} 下的子目录:`);
  subs.forEach((s, i) => console.log(`  [${i + 1}] ${s}`));
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const raw = await ask(rl, '\n输入要合并的序号(空格/逗号分隔，如 1 3 5): ');
  rl.close();
  const idx = raw.split(/[\s,]+/).filter(Boolean).map(Number);
  const chosen = idx.filter((n) => n >= 1 && n <= subs.length).map((n) => path.join(parent, subs[n - 1]));
  if (!chosen.length) die('未选择任何目录');
  return chosen;
}

// ---- 子命令解析 ----
const [cmd, ...rest] = process.argv.slice(2);

function getFlag(name) {
  const i = rest.indexOf('--' + name);
  if (i === -1) return null;
  // 收集到下一个 --flag 为止
  const vals = [];
  for (let j = i + 1; j < rest.length && !rest[j].startsWith('--'); j++) vals.push(rest[j]);
  return vals;
}

async function cmdCreate() {
  let base = (getFlag('base') || [])[0];
  let name = (getFlag('name') || [])[0];
  let members = getFlag('members') || [];
  const pick = (getFlag('pick') || [])[0];

  if (pick) {
    base = base || path.dirname(pick);
    members = await pickSubdirs(pick);
  }
  if (!members.length) die('未指定成员项目，用 --members <路径...> 或 --pick <父目录>');

  base = path.resolve(base || process.cwd());
  assertDir(base, '父目录(--base)');

  if (!name) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    name = await ask(rl, '工作区名称: ');
    rl.close();
  }
  if (!name) die('必须提供工作区名称 --name');

  const wsDir = path.join(base, name);
  if (fs.existsSync(wsDir)) die(`工作区已存在: ${wsDir}（如需追加用 add 命令）`);
  fs.mkdirSync(wsDir, { recursive: true });

  console.log(`\n创建工作区: ${wsDir}`);
  const added = linkMembers(wsDir, members);
  writeManifest(wsDir, { name, base, createdOn: 'taskspace', members: added });

  console.log(`\n✓ 完成。${added.length} 个项目已链接。`);
  console.log(`  下一步: cd "${wsDir}"   或在 Claude Code 里把它设为工作目录。`);
}

function cmdList() {
  const wsDir = path.resolve(rest[0] || '.');
  const m = readManifest(wsDir);
  if (!m) die(`不是 taskspace 工作区(缺 ${MANIFEST}): ${wsDir}`);
  console.log(`工作区: ${m.name}  (${wsDir})`);
  for (const mem of m.members) {
    const live = isLink(path.join(wsDir, mem.link));
    console.log(`  ${live ? '●' : '○(链接缺失)'} ${mem.link}  →  ${mem.target}`);
  }
}

function cmdAdd() {
  const wsDir = path.resolve(rest[0]);
  const m = readManifest(wsDir) || die('不是 taskspace 工作区');
  const added = linkMembers(wsDir, rest.slice(1));
  m.members.push(...added);
  writeManifest(wsDir, m);
  console.log(`✓ 已追加 ${added.length} 个。`);
}

function cmdRemove() {
  const wsDir = path.resolve(rest[0]);
  const m = readManifest(wsDir) || die('不是 taskspace 工作区');
  for (const linkName of rest.slice(1)) {
    const r = removeLink(path.join(wsDir, linkName));
    console.log(r.ok ? `  - ${linkName} 已移除` : `  ! ${linkName}: ${r.reason}`);
    if (r.ok) m.members = m.members.filter((x) => x.link !== linkName);
  }
  writeManifest(wsDir, m);
}

function cmdTeardown() {
  const wsDir = path.resolve(rest[0]);
  const m = readManifest(wsDir);
  if (!m) die(`不是 taskspace 工作区(缺 ${MANIFEST})，为安全起见拒绝删除: ${wsDir}`);
  for (const mem of m.members) {
    const r = removeLink(path.join(wsDir, mem.link));
    console.log(r.ok ? `  - ${mem.link}` : `  ! ${mem.link}: ${r.reason}`);
  }
  fs.rmSync(path.join(wsDir, MANIFEST), { force: true });
  // 仅当目录已空才删除目录本身
  if (fs.readdirSync(wsDir).length === 0) {
    fs.rmdirSync(wsDir);
    console.log(`✓ 工作区目录已清空并删除: ${wsDir}`);
  } else {
    console.log(`✓ 链接已拆除。目录非空(还有非链接文件)，保留: ${wsDir}`);
  }
  console.log('  源项目目录未被触碰。');
}

const dispatch = {
  create: cmdCreate, list: cmdList, add: cmdAdd, remove: cmdRemove, teardown: cmdTeardown,
};

(async () => {
  if (!cmd || !dispatch[cmd]) {
    console.log(`taskspace —— 跨平台合并工作区

  create   创建工作区并链接项目
  list     查看工作区成员
  add      追加项目
  remove   移除某个链接(只删链接)
  teardown 拆除整个工作区(只删链接+清单，不动源项目)

示例:
  node taskspace.mjs create --pick D:\\bigdir          # 交互多选
  node taskspace.mjs create --base D:\\ws --name 任务A --members D:\\a\\p1 D:\\b\\p2
  node taskspace.mjs teardown D:\\ws\\任务A`);
    process.exit(cmd ? 1 : 0);
  }
  try { await dispatch[cmd](); }
  catch (e) { die(e.message); }
})();
