#!/usr/bin/env bash
# update-team-tools.sh —— macOS / Linux 版「自动刷新公司团队套件」，对照 update-team-tools.ps1。
#   [MCP 仓] git pull project-domain-knowledge / cross-project-topology
#            project-domain-knowledge 有更新 -> npm install + npm run build
#            内容有更新则幂等重注册 domain-knowledge / cross-topology 两个 MCP 实例
#   [插件]   claude plugin marketplace update 刷源 -> claude plugin update <p>@<p> 逐个更新
#            (team-standards / project-coding-profiles / yoooni-daily-plugin)，幂等
# 被 SessionStart hook(session-autoupdate.js, darwin/linux 分支)、launchd 计划任务、更新 skill 共用。
# 用法: bash update-team-tools.sh [-s user|local|project] [-w <workspaceDir>]
set -u

MCP_SCOPE="user"
WORKSPACE_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--scope) MCP_SCOPE="${2:-user}"; shift 2 ;;
    -w|--workspace) WORKSPACE_DIR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

STATE_DIR="$HOME/.kai-toolbox"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/team-tools-update.log"
NOTICE="$STATE_DIR/team-tools-update.notice"
CFG="$STATE_DIR/workspace.path"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }
has() { command -v "$1" >/dev/null 2>&1; }

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

if [ "$PDK_CHANGED" = "1" ] && has npm; then
  log "  npm install/build (engine updated)"
  ( cd "$MCP_DIR" && npm install 2>&1 | while IFS= read -r l; do log "  npm $l"; done && npm run build 2>&1 | while IFS= read -r l; do log "  build $l"; done )
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
