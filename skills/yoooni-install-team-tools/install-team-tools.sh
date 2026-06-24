#!/usr/bin/env bash
# install-team-tools.sh —— macOS/Linux 版「一键首次安装」（全部走 Gitee 源），对照 install-team-tools.ps1。
# 只装【缺失的部分】：已安装的一律跳过，不重装/不更新——更新请用 update-team-tools.sh。
#   仓库：缺失才 git clone；MCP：未注册才 build + claude mcp add；插件：未装才 marketplace add + plugin install
# 用法: bash install-team-tools.sh [-w <workspaceDir>] [-s user|local|project]
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
STATE_DIR="$HOME/.kai-toolbox"; mkdir -p "$STATE_DIR"
CFG="$STATE_DIR/workspace.path"
GITEE="https://gitee.com/wyoooni"

if ! has git; then echo "未检测到 git，请先安装 Git 并加入 PATH。" >&2; exit 1; fi
has node && has npm && HAS_NODE=1 || HAS_NODE=0
has claude && HAS_CLAUDE=1 || HAS_CLAUDE=0

has_pdk() { [ -n "$1" ] && [ -d "$1/project-domain-knowledge/.git" ]; }
# --- 定位 WorkspaceDir：优先复用已克隆目录 ---
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
echo " 公司团队工具一键【首次安装】（Gitee 源）"
echo " 已安装的不重装/不更新 —— 更新请用 update-team-tools.sh"
echo "=================================================="
echo "工作区目录: $WORKSPACE_DIR"
echo "安装范围  : $SCOPE"
[ "$HAS_NODE" = "0" ] && echo "[warn] 未检测到 node/npm(>=18)，MCP 构建会被跳过。"
[ "$HAS_CLAUDE" = "0" ] && echo "[warn] 未检测到 claude CLI，MCP/插件自动安装会被跳过。"

new_repos=""; have_repos=""; new_mcp=""; new_plugins=""

# --- 第 1 步：克隆缺失仓库 ---
echo ""; echo "[1/3] 克隆缺失仓库（已存在跳过）..."
for r in team-standards project-coding-profiles project-domain-knowledge cross-project-topology; do
  dest="$WORKSPACE_DIR/$r"
  if [ -d "$dest/.git" ]; then echo "  = 已存在，跳过: $r"; have_repos="$have_repos $r"
  else echo "  + 克隆 $r"; git clone "$GITEE/$r.git" "$dest" && new_repos="$new_repos $r"; fi
done

# --- 第 2 步：MCP（复用 project-domain-knowledge 引擎，DOMAIN_KB_DIR 指不同知识根）---
echo ""; echo "[2/3] 注册 MCP（domain-knowledge + cross-topology，已注册跳过）..."
MCP_DIR="$WORKSPACE_DIR/project-domain-knowledge"; ENTRY="$MCP_DIR/dist/server.js"
DOMAIN_KB="$MCP_DIR/knowledge"; TOPO_KB="$WORKSPACE_DIR/cross-project-topology/knowledge"
mcp_registered() { [ "$HAS_CLAUDE" = "1" ] && claude mcp list 2>/dev/null | grep -qE "^[[:space:]]*$1\b"; }
if [ "$HAS_CLAUDE" = "1" ]; then
  need_domain=1; mcp_registered domain-knowledge && need_domain=0
  need_topo=0; [ -d "$TOPO_KB" ] && ! mcp_registered cross-topology && need_topo=1
  if { [ "$need_domain" = "1" ] || [ "$need_topo" = "1" ]; } && [ "$HAS_NODE" = "1" ]; then
    [ -f "$ENTRY" ] || ( cd "$MCP_DIR" && echo "  -> npm install" && npm install && echo "  -> npm run build" && npm run build )
    if [ -f "$ENTRY" ]; then
      if [ "$need_domain" = "1" ]; then
        echo "  + 注册 domain-knowledge"; claude mcp add domain-knowledge -s "$SCOPE" -e "DOMAIN_KB_DIR=$DOMAIN_KB" -- node "$ENTRY" && new_mcp="$new_mcp domain-knowledge"
      fi
      if [ "$need_topo" = "1" ]; then
        echo "  + 注册 cross-topology"; claude mcp add cross-topology -s "$SCOPE" -e "DOMAIN_KB_DIR=$TOPO_KB" -- node "$ENTRY" && new_mcp="$new_mcp cross-topology"
      fi
    else echo "  [warn] 构建后未找到 $ENTRY，跳过 MCP 注册。"; fi
  else echo "  = MCP 已注册或缺 node/npm，跳过"; fi
  [ ! -d "$TOPO_KB" ] && echo "  [warn] 未找到 $TOPO_KB，cross-topology 未注册（内容就绪后跑 update 刷新）。"
fi

# --- 第 3 步：插件（claude plugin CLI，已安装跳过）---
echo ""; echo "[3/3] 安装插件（已安装跳过）..."
if [ "$HAS_CLAUDE" = "1" ]; then
  plist="$(claude plugin list 2>/dev/null)"; mkt="$(claude plugin marketplace list 2>/dev/null)"
  for p in team-standards project-coding-profiles; do
    ref="${p}@${p}"
    if printf '%s' "$plist" | grep -qF "$ref"; then echo "  = 已安装，跳过: $ref"; continue; fi
    printf '%s' "$mkt" | grep -qF "$p" || { echo "  + marketplace add $p"; claude plugin marketplace add "$GITEE/$p.git"; }
    echo "  + plugin install $ref"; claude plugin install "$ref" -s "$SCOPE" && new_plugins="$new_plugins $p"
  done
else
  echo "  [warn] claude CLI 缺失，插件未安装。装好后手动："
  echo "    claude plugin marketplace add $GITEE/team-standards.git && claude plugin install team-standards@team-standards -s $SCOPE"
  echo "    claude plugin marketplace add $GITEE/project-coding-profiles.git && claude plugin install project-coding-profiles@project-coding-profiles -s $SCOPE"
fi

echo ""; echo "==================== 安装结果 ===================="
[ -n "$new_repos" ] && echo "新克隆仓库 :$new_repos"
[ -n "$new_mcp" ] && echo "新注册 MCP :$new_mcp"
[ -n "$new_plugins" ] && echo "新安装插件 :$new_plugins"
[ -z "$new_repos$new_mcp$new_plugins" ] && echo "本次没有新安装项——全部已就绪。"
[ -n "$new_plugins" ] && echo "插件已安装，重启 Claude Code 会话后生效。"
echo "更新请用 update-team-tools.sh（git pull + 重建 MCP + claude plugin update），别重跑安装。"
echo "=================================================="
