#!/usr/bin/env bash
# update-team-tools.sh —— macOS / Linux 版「自动刷新公司团队套件」，对照 update-team-tools.ps1。
#   [MCP 仓] git pull project-domain-knowledge / cross-project-topology
#            project-domain-knowledge 有更新 -> npm ci（有 lockfile）+ npm run build
#            内容有更新则幂等重注册 domain-knowledge / cross-topology 两个 MCP 实例
#   [插件]   claude plugin marketplace update 刷源 -> claude plugin update <p>@<p> 逐个更新
#            (team-standards / project-coding-profiles / yoooni-daily-plugin)，幂等
# 被 SessionStart hook(session-autoupdate.js, darwin/linux 分支)、launchd 计划任务、更新 skill 共用。
# 用法: bash update-team-tools.sh [-s user|local|project] [-w <workspaceDir>]
set -u -o pipefail

MCP_SCOPE="user"
WORKSPACE_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--scope) MCP_SCOPE="${2:-user}"; shift 2 ;;
    -w|--workspace) WORKSPACE_DIR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/update-lock.sh"
STATE_DIR="$HOME/.kai-toolbox"
acquire_yoooni_update_lock "$STATE_DIR" || exit 0
trap 'release_yoooni_update_lock' EXIT INT TERM
LOG="$STATE_DIR/team-tools-update.log"
NOTICE="$STATE_DIR/team-tools-update.notice"
CFG="$STATE_DIR/workspace.path"
log() {
  if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 10485760 ]; then mv -f "$LOG" "$LOG.1"; fi
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"
}
has() { command -v "$1" >/dev/null 2>&1; }
toml_path() { printf '%s' "$1" | sed 's#\\#/#g; s#"#\\"#g'; }
find_repo_dir() {
  name="$1"
  candidate="$WORKSPACE_DIR/$name"
  if [ -d "$candidate/.git" ]; then printf '%s' "$candidate"; return; fi
  dir="$SCRIPT_DIR"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ "$(basename "$dir")" = "$name" ] && [ -d "$dir/.git" ]; then printf '%s' "$dir"; return; fi
    dir="$(dirname "$dir")"
  done
  printf '%s' "$candidate"
}
codex_plugin_dir() {
  repo="$1"; plugin="$2"
  if [ -f "$repo/plugins/$plugin/.codex-plugin/plugin.json" ]; then printf '%s' "$repo/plugins/$plugin"; return; fi
  if [ -f "$repo/.codex-plugin/plugin.json" ]; then printf '%s' "$repo"; return; fi
  printf '%s' "$repo/plugins/$plugin"
}
sync_codex_mcp_server() {
  name="$1"; entry="$2"; kb="$3"
  codex_root="$HOME/.codex"
  codex_cfg="$codex_root/config.toml"
  [ -d "$codex_root" ] || { log "  codex: ~/.codex not found, skip MCP config"; return 0; }
  mkdir -p "$(dirname "$codex_cfg")"
  [ -f "$codex_cfg" ] || : > "$codex_cfg"
  [ "$(wc -c < "$codex_cfg")" -le 16777216 ] || { log "  codex: config exceeds 16MB, refuse to modify"; return 1; }
  tmp="$codex_cfg.tmp.$$"
  base="$tmp.base"
  cp "$codex_cfg" "$base"
  awk -v name="$name" '
    /^\[/ {
      if ($0 == "[mcp_servers.\"" name "\"]" || $0 == "[mcp_servers." name "]") {
        skip = 1
        next
      }
      skip = 0
    }
    !skip { print }
  ' "$base" > "$tmp"
  {
    printf '\n[mcp_servers."%s"]\n' "$name"
    printf 'command = "node"\n'
    printf 'args = ["%s"]\n' "$(toml_path "$entry")"
    printf 'env = { "DOMAIN_KB_DIR" = "%s" }\n' "$(toml_path "$kb")"
  } >> "$tmp"
  if ! cmp -s "$base" "$codex_cfg"; then rm -f "$tmp" "$base"; log "  codex: config changed concurrently, refuse to overwrite"; return 1; fi
  cp "$base" "$codex_cfg.yoooni-safe.bak"
  mv "$tmp" "$codex_cfg"
  rm -f "$base"
  log "  codex: MCP config synced -> $name"
}
sync_json_mcp_config() {
  tool="$1"; root="$2"; cfg="$3"; entry="$4"; domain_kb="$5"; topo_kb="$6"
  [ -d "$root" ] || { log "  $tool: root not found, skip MCP config"; return 0; }
  has node || { log "  $tool: node not found, skip MCP config"; return 0; }
  TOOL_NAME="$tool" MCP_JSON_CONFIG="$cfg" MCP_ENTRY="$entry" DOMAIN_KB="$domain_kb" TOPO_KB="$topo_kb" node <<'NODE'
const fs = require('fs');
const path = require('path');
const cfg = process.env.MCP_JSON_CONFIG;
const entry = process.env.MCP_ENTRY.replace(/\\/g, '/');
const domainKb = process.env.DOMAIN_KB.replace(/\\/g, '/');
const topoKb = (process.env.TOPO_KB || '').replace(/\\/g, '/');
let root = {};
try {
  if (fs.existsSync(cfg)) root = JSON.parse(fs.readFileSync(cfg, 'utf8'));
} catch {
  root = {};
}
if (!root || typeof root !== 'object' || Array.isArray(root)) root = {};
if (!root.mcpServers || typeof root.mcpServers !== 'object' || Array.isArray(root.mcpServers)) {
  root.mcpServers = {};
}
root.mcpServers['domain-knowledge'] = {
  command: 'node',
  args: [entry],
  env: { DOMAIN_KB_DIR: domainKb },
};
if (topoKb && fs.existsSync(topoKb)) {
  root.mcpServers['cross-topology'] = {
    command: 'node',
    args: [entry],
    env: { DOMAIN_KB_DIR: topoKb },
  };
}
fs.mkdirSync(path.dirname(cfg), { recursive: true });
fs.writeFileSync(cfg, JSON.stringify(root, null, 2));
NODE
  log "  $tool: MCP config synced"
}
sync_codex_plugins() {
  codex_root="$HOME/.codex"
  [ -d "$codex_root" ] || { log "  codex: ~/.codex not found, skip plugin sync"; return 0; }
  has node || { log "  codex: node not found, skip plugin sync"; return 0; }

  team_repo="$(find_repo_dir team-standards)"
  profiles_repo="$(find_repo_dir project-coding-profiles)"
  daily_repo="$(find_repo_dir yoooni-daily-plugin)"
  CODEX_ROOT="$codex_root" \
  TEAM_REPO="$team_repo" TEAM_PLUGIN_DIR="$(codex_plugin_dir "$team_repo" team-standards)" \
  PROFILES_REPO="$profiles_repo" PROFILES_PLUGIN_DIR="$(codex_plugin_dir "$profiles_repo" project-coding-profiles)" \
  DAILY_REPO="$daily_repo" DAILY_PLUGIN_DIR="$(codex_plugin_dir "$daily_repo" yoooni-daily-plugin)" node <<'NODE'
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const codexRoot = process.env.CODEX_ROOT;
const configPath = path.join(codexRoot, 'config.toml');
const cacheRoot = path.join(codexRoot, 'plugins', 'cache');
const plugins = [
  { name: 'team-standards', marketplace: 'team-standards', url: 'https://gitee.com/wyoooni/team-standards.git', repo: process.env.TEAM_REPO, dir: process.env.TEAM_PLUGIN_DIR },
  { name: 'project-coding-profiles', marketplace: 'project-coding-profiles', url: 'https://gitee.com/wyoooni/project-coding-profiles.git', repo: process.env.PROFILES_REPO, dir: process.env.PROFILES_PLUGIN_DIR },
  { name: 'yoooni-daily-plugin', marketplace: 'yoooni-daily-plugin', url: 'https://gitee.com/wyoooni/yoooni-daily-plugin.git', repo: process.env.DAILY_REPO, dir: process.env.DAILY_PLUGIN_DIR },
];
function rev(repo) {
  try { return cp.execFileSync('git', ['-C', repo, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(); } catch { return ''; }
}
function tableRegex(kind, key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^\\[${kind}\\.${kind === 'plugins' ? '"' : ''}${escaped}${kind === 'plugins' ? '"' : ''}\\]\\s*\\r?\\n.*?(?=^\\[|(?![\\s\\S]))`, 'ms');
}
function putBlock(text, regex, block) {
  if (regex.test(text)) return text.replace(regex, block.trimStart());
  const sep = text && !text.endsWith('\n') ? '\n' : '';
  return text + sep + block;
}
fs.mkdirSync(path.dirname(configPath), { recursive: true });
let text = fs.existsSync(configPath) ? fs.readFileSync(configPath, 'utf8') : '';
if (Buffer.byteLength(text, 'utf8') > 16 * 1024 * 1024) throw new Error('Refuse to modify Codex config larger than 16MB');
const originalText = text;
const synced = [];
for (const p of plugins) {
  const manifestPath = path.join(p.dir, '.codex-plugin', 'plugin.json');
  if (!fs.existsSync(manifestPath)) continue;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const version = manifest.version || '0.0.0';
  const target = path.resolve(cacheRoot, p.marketplace, p.name, version);
  const cacheAbs = path.resolve(cacheRoot);
  if (!target.startsWith(cacheAbs + path.sep)) throw new Error(`Refuse to write outside cache: ${target}`);
  const staging = `${target}.staging.${process.pid}`;
  fs.rmSync(staging, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.cpSync(p.dir, staging, { recursive: true });
  if (!fs.existsSync(path.join(staging, '.codex-plugin', 'plugin.json'))) throw new Error(`Invalid staged plugin: ${staging}`);
  fs.rmSync(target, { recursive: true, force: true });
  fs.renameSync(staging, target);
  const updated = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  const marketBlock = `\n[marketplaces.${p.marketplace}]\nlast_updated = "${updated}"\n${rev(p.repo) ? `last_revision = "${rev(p.repo)}"\n` : ''}source_type = "git"\nsource = "${p.url}"\n`;
  const pluginRef = `${p.name}@${p.marketplace}`;
  const pluginBlock = `\n[plugins."${pluginRef}"]\nenabled = true\n`;
  const marketRegex = tableRegex('marketplaces', p.marketplace);
  const currentMarket = text.match(marketRegex)?.[0] || '';
  const stable = (value) => value.replace(/^last_updated\s*=.*\r?\n?/m, '').trim();
  if (!currentMarket || stable(currentMarket) !== stable(marketBlock)) text = putBlock(text, marketRegex, marketBlock);
  text = putBlock(text, tableRegex('plugins', pluginRef), pluginBlock);
  synced.push(`${pluginRef}@${version}`);
}
if (text !== originalText) {
  const tmp = `${configPath}.tmp.${process.pid}`;
  const backup = `${configPath}.yoooni-safe.bak`;
  fs.writeFileSync(tmp, text, 'utf8');
  const currentText = fs.existsSync(configPath) ? fs.readFileSync(configPath, 'utf8') : '';
  if (currentText !== originalText) { fs.rmSync(tmp, { force: true }); throw new Error('Codex config changed concurrently; refusing to overwrite'); }
  if (fs.existsSync(configPath)) fs.copyFileSync(configPath, backup);
  fs.renameSync(tmp, configPath);
}
console.log(synced.join(','));
NODE
  log "  codex: plugin sync complete"
}
sync_cursor_rules() {
  [ -d "$HOME/.cursor" ] || { log "  cursor: root not found, skip rules sync"; return 0; }
  profiles_repo="$(find_repo_dir project-coding-profiles)"
  rules_dir="$profiles_repo/plugins/project-coding-profiles/.cursor/rules"
  [ -d "$rules_dir" ] || { log "  cursor: source rules not found, skip"; return 0; }
  mkdir -p "$HOME/.cursor/rules"
  for f in "$rules_dir"/*.mdc; do
    [ -f "$f" ] || continue
    cp -f "$f" "$HOME/.cursor/rules/yoooni-$(basename "$f")"
  done
  log "  cursor: rules synced"
}
sync_kiro_steering() {
  [ -d "$HOME/.kiro" ] || { log "  kiro: root not found, skip steering sync"; return 0; }
  mkdir -p "$HOME/.kiro/steering"
  {
    printf '# Yoooni Team Tools\n\n'
    printf 'Use the installed Yoooni team tools as the default coding guidance for company projects.\n\n'
    printf 'Workspace: %s\n' "$WORKSPACE_DIR"
    printf 'team-standards: %s\n' "$(find_repo_dir team-standards)"
    printf 'project-coding-profiles: %s\n' "$(find_repo_dir project-coding-profiles)"
    printf 'yoooni-daily-plugin: %s\n\n' "$(find_repo_dir yoooni-daily-plugin)"
    printf 'Before editing code, follow the relevant coding standards, project profile, encoding profile, and registered MCP knowledge sources.\n'
  } > "$HOME/.kiro/steering/yoooni-team-tools.md"
  log "  kiro: steering synced"
}

# --- 定位 WorkspaceDir：参数 > 环境变量 > 配置 > claude mcp 解析 > 默认 $HOME/myWork ---
if [ -z "$WORKSPACE_DIR" ] && [ -n "${YOOONI_WORKSPACE_DIR:-}" ]; then WORKSPACE_DIR="$YOOONI_WORKSPACE_DIR"; fi
if [ -z "$WORKSPACE_DIR" ] && [ -f "$CFG" ]; then WORKSPACE_DIR="$(tr -d '\r\357\273\277' < "$CFG" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"; fi
if [ -z "$WORKSPACE_DIR" ] && has claude; then
  _info="$( { claude mcp get domain-knowledge 2>/dev/null; claude mcp list 2>/dev/null; } )"
  _m="$(printf '%s\n' "$_info" | grep -oE '(/[^[:space:]]+)/project-domain-knowledge/dist/server\.js' | head -n1)"
  if [ -n "$_m" ]; then WORKSPACE_DIR="${_m%/project-domain-knowledge/dist/server.js}"; fi
fi
[ -z "$WORKSPACE_DIR" ] && WORKSPACE_DIR="$HOME/myWork"
printf '%s' "$WORKSPACE_DIR" > "$CFG"   # 记住，下次直接用

log "=== update start (ws=$WORKSPACE_DIR, scope=$MCP_SCOPE) ==="
MCP_DIR="$WORKSPACE_DIR/project-domain-knowledge"
TOPO_DIR="$WORKSPACE_DIR/cross-project-topology"
PDK_CHANGED=0
ANY_CHANGED=0

for d in "$MCP_DIR" "$TOPO_DIR"; do
  if [ -d "$d/.git" ]; then
    before="$(git -C "$d" rev-parse HEAD 2>/dev/null)"
    git -C "$d" pull --ff-only 2>&1 | while IFS= read -r line; do log "  git $line"; done
    after="$(git -C "$d" rev-parse HEAD 2>/dev/null)"
    if [ "$before" != "$after" ]; then
      ANY_CHANGED=1
      [ "$d" = "$MCP_DIR" ] && PDK_CHANGED=1
    fi
  else
    log "  skip (not cloned): $d"
  fi
done

for repo_name in team-standards project-coding-profiles yoooni-daily-plugin; do
  repo_dir="$(find_repo_dir "$repo_name")"
  if [ -d "$repo_dir/.git" ]; then
    git -C "$repo_dir" pull --ff-only 2>&1 | while IFS= read -r line; do log "  git plugin $line"; done
  else
    log "  skip plugin repo (not cloned): $repo_dir"
  fi
done

if [ "$PDK_CHANGED" = "1" ] && has npm; then
  if [ -f "$MCP_DIR/package-lock.json" ]; then
    log "  npm ci/build (engine updated)"
    ( cd "$MCP_DIR" && npm ci --no-audit --no-fund 2>&1 | while IFS= read -r l; do log "  npm $l"; done && npm run build 2>&1 | while IFS= read -r l; do log "  build $l"; done )
  else
    log "  npm install/build (engine updated; no package-lock.json)"
    ( cd "$MCP_DIR" && npm install --no-audit --no-fund 2>&1 | while IFS= read -r l; do log "  npm $l"; done && npm run build 2>&1 | while IFS= read -r l; do log "  build $l"; done )
  fi
fi

ENTRY="$MCP_DIR/dist/server.js"
# 仅当仓库内容有更新时才重注册(触发 MCP 下次会话重启、加载新知识/引擎)；无变化不动
if [ "$ANY_CHANGED" = "1" ] && has claude && [ -f "$ENTRY" ]; then
  DOMAIN_KB="$MCP_DIR/knowledge"
  TOPO_KB="$TOPO_DIR/knowledge"
  claude mcp remove domain-knowledge -s "$MCP_SCOPE" >/dev/null 2>&1
  claude mcp add domain-knowledge -s "$MCP_SCOPE" -e "DOMAIN_KB_DIR=$DOMAIN_KB" -- node "$ENTRY" 2>&1 | while IFS= read -r l; do log "  mcp $l"; done
  if [ -d "$TOPO_KB" ]; then
    claude mcp remove cross-topology -s "$MCP_SCOPE" >/dev/null 2>&1
    claude mcp add cross-topology -s "$MCP_SCOPE" -e "DOMAIN_KB_DIR=$TOPO_KB" -- node "$ENTRY" 2>&1 | while IFS= read -r l; do log "  mcp $l"; done
  fi
fi

if [ -f "$ENTRY" ]; then
  DOMAIN_KB="$MCP_DIR/knowledge"
  TOPO_KB="$TOPO_DIR/knowledge"
  sync_codex_mcp_server "domain-knowledge" "$ENTRY" "$DOMAIN_KB"
  if [ -d "$TOPO_KB" ]; then
    sync_codex_mcp_server "cross-topology" "$ENTRY" "$TOPO_KB"
  fi
  sync_json_mcp_config "cursor" "$HOME/.cursor" "$HOME/.cursor/mcp.json" "$ENTRY" "$DOMAIN_KB" "$TOPO_KB"
  sync_json_mcp_config "kiro" "$HOME/.kiro" "$HOME/.kiro/settings/mcp.json" "$ENTRY" "$DOMAIN_KB" "$TOPO_KB"
fi

sync_codex_plugins
sync_cursor_rules
sync_kiro_steering

# --- 插件：claude plugin 全自动更新；必须用全限定名 <p>@<p>（裸名会报 not found）---
PLUGIN_NOTICE=""
if has claude; then
  claude plugin marketplace update 2>&1 | while IFS= read -r l; do log "  mkt $l"; done
  for p in team-standards project-coding-profiles yoooni-daily-plugin; do
    out="$(claude plugin update "${p}@${p}" -s "$MCP_SCOPE" 2>&1)"
    printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | while IFS= read -r l; do log "  plg $l"; done
    ver="$(printf '%s\n' "$out" | grep -oE 'updated from[[:space:]]+[^[:space:]]+[[:space:]]+to[[:space:]]+[^[:space:]]+' | head -n1)"
    if [ -n "$ver" ]; then
      from="$(printf '%s' "$ver" | awk '{print $3}')"; to="$(printf '%s' "$ver" | awk '{print $5}')"
      [ -n "$PLUGIN_NOTICE" ] && PLUGIN_NOTICE="$PLUGIN_NOTICE；"
      PLUGIN_NOTICE="${PLUGIN_NOTICE}${p} ${from}→${to}"
    fi
  done
fi
if [ -n "$PLUGIN_NOTICE" ]; then
  printf '团队插件已自动更新：%s。重启 Claude Code 会话即生效。' "$PLUGIN_NOTICE" > "$NOTICE"
else
  : > "$NOTICE"
fi

# --- best-effort 同步 hook 命中事件到公司共享（仅当已挂载 /Volumes/版本更新/vibecoding 时）---
EV_LOCAL="$STATE_DIR/hook-events.jsonl"
EV_SHARE="/Volumes/版本更新/vibecoding"
if [ -f "$EV_LOCAL" ]; then
  if [ -d "$EV_SHARE" ]; then
    cp -f "$EV_LOCAL" "$EV_SHARE/hook-events-$(id -un)-$(scutil --get ComputerName 2>/dev/null || hostname).jsonl" 2>/dev/null && log "  hooklog synced -> $EV_SHARE" || log "  hooklog sync skipped"
  else
    log "  hooklog: 共享 $EV_SHARE 未挂载，跳过同步"
  fi
fi

# --- 自愈：若 launchd 计划任务已存在，确保它指向稳定启动器（仅当已存在，绝不擅自创建）---
REG="$(dirname "$0")/register-autoupdate-task.sh"
if [ -f "$REG" ]; then
  bash "$REG" --only-if-exists >/dev/null 2>&1 && log "  task: 自愈校准 launchd（仅当已存在）" || true
fi

log "=== update done (pdkChanged=$PDK_CHANGED, pluginNotice=${PLUGIN_NOTICE:-none}) ==="
