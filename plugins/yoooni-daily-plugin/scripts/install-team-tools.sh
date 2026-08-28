#!/usr/bin/env bash
# One-click first install for the Yoooni team tools on macOS/Linux.
# Existing items are skipped; updates should use scripts/update-team-tools.sh.
set -u

WORKSPACE_DIR=""
SCOPE="user"
while [ $# -gt 0 ]; do
  case "$1" in
    -w|--workspace) WORKSPACE_DIR="${2:-}"; shift 2 ;;
    -s|--scope) SCOPE="${2:-user}"; shift 2 ;;
    *) shift ;;
  esac
done

has() { command -v "$1" >/dev/null 2>&1; }
STATE_DIR="$HOME/.kai-toolbox"
mkdir -p "$STATE_DIR"
CFG="$STATE_DIR/workspace.path"
GITEE="https://gitee.com/wyoooni"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! has git; then
  echo "git is required. Please install Git and ensure it is in PATH." >&2
  exit 1
fi
has node && has npm && HAS_NODE=1 || HAS_NODE=0
has claude && HAS_CLAUDE=1 || HAS_CLAUDE=0

has_pdk() { [ -n "${1:-}" ] && [ -d "$1/project-domain-knowledge/.git" ]; }
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

add_codex_mcp_server() {
  name="$1"; entry="$2"; kb="$3"
  codex_root="$HOME/.codex"
  codex_cfg="$codex_root/config.toml"
  [ -d "$codex_root" ] || { echo "  - Codex not installed, skip MCP config"; return 0; }
  mkdir -p "$(dirname "$codex_cfg")"
  [ -f "$codex_cfg" ] || : > "$codex_cfg"
  [ "$(wc -c < "$codex_cfg")" -le 16777216 ] || { echo "  ! Codex config exceeds 16MB; refusing to modify it" >&2; return 1; }
  if grep -Eq "^[[:space:]]*\\[mcp_servers\\.(\"$name\"|$name)\\]" "$codex_cfg"; then
    echo "  = Codex: $name already exists, skip"
    return 0
  fi
  tmp="$codex_cfg.tmp.$$"
  base="$tmp.base"
  cp "$codex_cfg" "$base"
  cp "$base" "$tmp"
  {
    printf '\n[mcp_servers."%s"]\n' "$name"
    printf 'command = "node"\n'
    printf 'args = ["%s"]\n' "$(toml_path "$entry")"
    printf 'env = { "DOMAIN_KB_DIR" = "%s" }\n' "$(toml_path "$kb")"
  } >> "$tmp"
  if ! cmp -s "$base" "$codex_cfg"; then rm -f "$tmp" "$base"; echo "  ! Codex config changed concurrently; refusing to overwrite" >&2; return 1; fi
  cp "$base" "$codex_cfg.yoooni-safe.bak"
  mv "$tmp" "$codex_cfg"
  rm -f "$base"
  echo "  + Codex: added $name -> $codex_cfg"
}

sync_json_mcp_config() {
  tool="$1"; root="$2"; cfg="$3"; entry="$4"; domain_kb="$5"; topo_kb="$6"
  [ -d "$root" ] || { echo "  - $tool not installed, skip MCP config"; return 0; }
  has node || { echo "  - $tool: node is not available, skip MCP config"; return 0; }
  MCP_JSON_CONFIG="$cfg" MCP_ENTRY="$entry" DOMAIN_KB="$domain_kb" TOPO_KB="$topo_kb" node <<'NODE'
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
if (!root.mcpServers || typeof root.mcpServers !== 'object' || Array.isArray(root.mcpServers)) root.mcpServers = {};
root.mcpServers['domain-knowledge'] = { command: 'node', args: [entry], env: { DOMAIN_KB_DIR: domainKb } };
if (topoKb && fs.existsSync(topoKb)) {
  root.mcpServers['cross-topology'] = { command: 'node', args: [entry], env: { DOMAIN_KB_DIR: topoKb } };
}
fs.mkdirSync(path.dirname(cfg), { recursive: true });
fs.writeFileSync(cfg, JSON.stringify(root, null, 2));
NODE
  echo "  + $tool: MCP config synced -> $cfg"
}

sync_codex_plugins() {
  codex_root="$HOME/.codex"
  [ -d "$codex_root" ] || { echo "  - Codex not installed, skip plugin sync"; return 0; }
  has node || { echo "  - Codex: node is not available, skip plugin sync"; return 0; }

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
function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function putBlock(text, kind, key, block) {
  const quoted = kind === 'plugins' ? `"${esc(key)}"` : esc(key);
  const re = new RegExp(`^\\[${kind}\\.${quoted}\\]\\s*\\r?\\n.*?(?=^\\[|(?![\\s\\S]))`, 'ms');
  if (re.test(text)) return text.replace(re, block.trimStart());
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
  const revision = rev(p.repo);
  const marketBlock = `\n[marketplaces.${p.marketplace}]\nlast_updated = "${updated}"\n${revision ? `last_revision = "${revision}"\n` : ''}source_type = "git"\nsource = "${p.url}"\n`;
  const pluginRef = `${p.name}@${p.marketplace}`;
  const marketPattern = new RegExp(`^\\[marketplaces\\.${esc(p.marketplace)}\\]\\s*\\r?\\n.*?(?=^\\[|(?![\\s\\S]))`, 'ms');
  const currentMarket = text.match(marketPattern)?.[0] || '';
  const stable = (value) => value.replace(/^last_updated\s*=.*\r?\n?/m, '').trim();
  if (!currentMarket || stable(currentMarket) !== stable(marketBlock)) text = putBlock(text, 'marketplaces', p.marketplace, marketBlock);
  text = putBlock(text, 'plugins', pluginRef, `\n[plugins."${pluginRef}"]\nenabled = true\n`);
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
  echo "  + Codex: plugin cache/config synced"
}

sync_cursor_rules() {
  [ -d "$HOME/.cursor" ] || { echo "  - Cursor not installed, skip rules sync"; return 0; }
  profiles_repo="$(find_repo_dir project-coding-profiles)"
  rules_dir="$profiles_repo/plugins/project-coding-profiles/.cursor/rules"
  [ -d "$rules_dir" ] || { echo "  - Cursor: source rules not found, skip"; return 0; }
  mkdir -p "$HOME/.cursor/rules"
  for f in "$rules_dir"/*.mdc; do
    [ -f "$f" ] || continue
    cp -f "$f" "$HOME/.cursor/rules/yoooni-$(basename "$f")"
  done
  echo "  + Cursor: rules synced"
}

sync_kiro_steering() {
  [ -d "$HOME/.kiro" ] || { echo "  - Kiro not installed, skip steering sync"; return 0; }
  mkdir -p "$HOME/.kiro/steering"
  {
    printf '# Yoooni Team Tools\n\n'
    printf 'Use the installed Yoooni team tools as the default coding guidance for company projects.\n\n'
    printf 'Workspace: %s\n' "$WORKSPACE_DIR"
    printf 'team-standards: %s\n' "$(find_repo_dir team-standards)"
    printf 'project-coding-profiles: %s\n' "$(find_repo_dir project-coding-profiles)"
    printf 'yoooni-daily-plugin: %s\n\n' "$(find_repo_dir yoooni-daily-plugin)"
    printf 'Before editing code, follow the relevant coding standards, project profile, encoding profile, and registered MCP knowledge sources.\n'
  } > "$HOME/.kiro/steering/team-tools-maintenance.md"
  echo "  + Kiro: steering synced"
}

resolved=""
for c in "$WORKSPACE_DIR" "${YOOONI_WORKSPACE_DIR:-}" "$([ -f "$CFG" ] && tr -d '\r\357\273\277' < "$CFG" | head -n1)" "$HOME/myWork"; do
  [ -n "$c" ] || continue
  if has_pdk "$c"; then resolved="$c"; break; fi
done
if [ -z "$resolved" ]; then
  if [ -n "$WORKSPACE_DIR" ]; then resolved="$WORKSPACE_DIR"
  elif [ -f "$CFG" ]; then resolved="$(tr -d '\r\357\273\277' < "$CFG" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  else resolved="$HOME/myWork"; fi
fi
WORKSPACE_DIR="$resolved"
printf '%s' "$WORKSPACE_DIR" > "$CFG"
mkdir -p "$WORKSPACE_DIR"

echo "=================================================="
echo " Yoooni team tools first install (Gitee source)"
echo " Existing items are skipped. Use update-team-tools.sh for updates."
echo "=================================================="
echo "Workspace: $WORKSPACE_DIR"
echo "Scope    : $SCOPE"
[ "$HAS_NODE" = "0" ] && echo "[warn] node/npm not found; MCP build and JSON/Codex sync may be skipped."
[ "$HAS_CLAUDE" = "0" ] && echo "[warn] claude CLI not found; Claude MCP/plugin install will be skipped."

new_repos=""; new_mcp=""; new_plugins=""; new_tool_plugins=""

echo ""; echo "[1/3] Clone missing repos..."
for r in team-standards project-coding-profiles project-domain-knowledge cross-project-topology; do
  dest="$WORKSPACE_DIR/$r"
  if [ -d "$dest/.git" ]; then
    echo "  = exists: $r"
  else
    echo "  + clone $r"
    git clone "$GITEE/$r.git" "$dest" && new_repos="$new_repos $r"
  fi
done

echo ""; echo "[2/3] Register Claude MCP servers..."
MCP_DIR="$WORKSPACE_DIR/project-domain-knowledge"
ENTRY="$MCP_DIR/dist/server.js"
DOMAIN_KB="$MCP_DIR/knowledge"
TOPO_KB="$WORKSPACE_DIR/cross-project-topology/knowledge"
mcp_registered() { [ "$HAS_CLAUDE" = "1" ] && claude mcp list 2>/dev/null | grep -qE "^[[:space:]]*$1\b"; }
if [ "$HAS_CLAUDE" = "1" ]; then
  need_domain=1; mcp_registered domain-knowledge && need_domain=0
  need_topo=0; [ -d "$TOPO_KB" ] && ! mcp_registered cross-topology && need_topo=1
  if { [ "$need_domain" = "1" ] || [ "$need_topo" = "1" ]; } && [ "$HAS_NODE" = "1" ]; then
    [ -f "$ENTRY" ] || ( cd "$MCP_DIR" && npm install && npm run build )
    if [ -f "$ENTRY" ]; then
      if [ "$need_domain" = "1" ]; then
        claude mcp add domain-knowledge -s "$SCOPE" -e "DOMAIN_KB_DIR=$DOMAIN_KB" -- node "$ENTRY" && new_mcp="$new_mcp domain-knowledge"
      fi
      if [ "$need_topo" = "1" ]; then
        claude mcp add cross-topology -s "$SCOPE" -e "DOMAIN_KB_DIR=$TOPO_KB" -- node "$ENTRY" && new_mcp="$new_mcp cross-topology"
      fi
    else
      echo "  [warn] MCP entry not found after build: $ENTRY"
    fi
  else
    echo "  = Claude MCP already registered, or node/npm is missing"
  fi
fi

echo ""; echo "[2.5] Register MCP for Codex / Cursor / Kiro..."
if [ -f "$ENTRY" ]; then
  add_codex_mcp_server "domain-knowledge" "$ENTRY" "$DOMAIN_KB"
  [ -d "$TOPO_KB" ] && add_codex_mcp_server "cross-topology" "$ENTRY" "$TOPO_KB"
  sync_json_mcp_config "Cursor" "$HOME/.cursor" "$HOME/.cursor/mcp.json" "$ENTRY" "$DOMAIN_KB" "$TOPO_KB"
  sync_json_mcp_config "Kiro" "$HOME/.kiro" "$HOME/.kiro/settings/mcp.json" "$ENTRY" "$DOMAIN_KB" "$TOPO_KB"
else
  echo "  - MCP entry not found, skip Codex/Cursor/Kiro MCP config"
fi

echo ""; echo "[2.6] Install plugin equivalents for Codex / Cursor / Kiro..."
sync_codex_plugins && new_tool_plugins="$new_tool_plugins Codex"
sync_cursor_rules && new_tool_plugins="$new_tool_plugins Cursor-rules"
sync_kiro_steering && new_tool_plugins="$new_tool_plugins Kiro-steering"

echo ""; echo "[3/3] Install Claude Code plugins..."
if [ "$HAS_CLAUDE" = "1" ]; then
  plist="$(claude plugin list 2>/dev/null)"
  mkt="$(claude plugin marketplace list 2>/dev/null)"
  for p in team-standards project-coding-profiles; do
    ref="${p}@${p}"
    if printf '%s' "$plist" | grep -qF "$ref"; then
      echo "  = installed: $ref"
      continue
    fi
    printf '%s' "$mkt" | grep -qF "$p" || claude plugin marketplace add "$GITEE/$p.git"
    claude plugin install "$ref" -s "$SCOPE" && new_plugins="$new_plugins $p"
  done
else
  echo "  [warn] claude CLI missing. Install Claude Code, then rerun this script."
fi

echo ""; echo "==================== Install result ===================="
[ -n "$new_repos" ] && echo "New repos:$new_repos"
[ -n "$new_mcp" ] && echo "New Claude MCP:$new_mcp"
[ -n "$new_tool_plugins" ] && echo "Synced tool plugin equivalents:$new_tool_plugins"
[ -n "$new_plugins" ] && echo "New Claude plugins:$new_plugins"
[ -z "$new_repos$new_mcp$new_tool_plugins$new_plugins" ] && echo "No new install items; everything was already present or skipped because the target tool is not installed."
echo "Use update-team-tools.sh for git pull + MCP rebuild + plugin updates."
echo "=================================================="
