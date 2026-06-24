#!/usr/bin/env bash
# uninstall-team-tools.sh —— macOS/Linux「一键卸载」，对照 uninstall-team-tools.ps1。
# 只摘本套件登记到 Claude Code 的项（白名单精确匹配），不碰其它插件/MCP：
#   插件 team-standards / project-coding-profiles / yoooni-daily-plugin；MCP domain-knowledge / cross-topology；
#   launchd 任务 com.yoooni.team-tools-autoupdate。默认保留源码仓与 marketplace 登记。
# 用法: bash uninstall-team-tools.sh [-s user|local|project] [--keep-task] [--remove-marketplace] [--remove-repos] [-w <ws>]
set -u
SCOPE="user"; REMOVE_TASK=1; REMOVE_MKT=0; REMOVE_REPOS=0; WORKSPACE_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--scope) SCOPE="${2:-user}"; shift 2 ;;
    --keep-task) REMOVE_TASK=0; shift ;;
    --remove-marketplace) REMOVE_MKT=1; shift ;;
    --remove-repos) REMOVE_REPOS=1; shift ;;
    -w|--workspace) WORKSPACE_DIR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
has() { command -v "$1" >/dev/null 2>&1; }
has claude && HAS_CLAUDE=1 || HAS_CLAUDE=0
LABEL="com.yoooni.team-tools-autoupdate"; PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "=================================================="
echo " 公司团队套件【一键卸载】（只摘本套件项）"
echo "=================================================="
[ "$HAS_CLAUDE" = "0" ] && echo "[warn] 未检测到 claude CLI —— 插件/MCP 无法卸载；launchd 任务仍会按设置删除。"

removed_plugins=""; removed_mcp=""
# --- 1) 卸载插件 ---
if [ "$HAS_CLAUDE" = "1" ]; then
  echo ""; echo "[1/3] 卸载插件..."
  pl="$(claude plugin list 2>/dev/null)"
  for p in team-standards project-coding-profiles yoooni-daily-plugin; do
    ref="${p}@${p}"
    if printf '%s' "$pl" | grep -qF "$ref"; then echo "  - plugin uninstall $ref"; claude plugin uninstall "$ref" -s "$SCOPE" -y; removed_plugins="$removed_plugins $p"
    else echo "  = 未安装，跳过: $ref"; fi
  done
  if [ "$REMOVE_MKT" = "1" ]; then
    echo "  移除 marketplace 登记..."
    for p in team-standards project-coding-profiles yoooni-daily-plugin; do claude plugin marketplace remove "$p" 2>/dev/null; done
  fi
fi

# --- 2) 移除 MCP ---
if [ "$HAS_CLAUDE" = "1" ]; then
  echo ""; echo "[2/3] 移除 MCP..."
  ml="$(claude mcp list 2>/dev/null)"
  for m in domain-knowledge cross-topology; do
    if printf '%s' "$ml" | grep -qE "^[[:space:]]*$m\b"; then
      echo "  - mcp remove $m"; claude mcp remove "$m" -s "$SCOPE" 2>/dev/null || claude mcp remove "$m" 2>/dev/null; removed_mcp="$removed_mcp $m"
    else echo "  = 未注册，跳过: $m"; fi
  done
fi

# --- 3) 删除 launchd 定时任务 ---
echo ""; echo "[3/3] 定时更新任务（launchd）..."
if [ "$REMOVE_TASK" = "1" ]; then
  if [ -f "$PLIST" ]; then launchctl unload "$PLIST" >/dev/null 2>&1 || true; rm -f "$PLIST"; echo "  - 已删除 launchd 任务 $LABEL"
  else echo "  = 任务不存在，跳过"; fi
else echo "  (保留定时任务)"; fi

# --- 可选：删源码仓库 ---
if [ "$REMOVE_REPOS" = "1" ]; then
  CFG="$HOME/.kai-toolbox/workspace.path"
  [ -z "$WORKSPACE_DIR" ] && [ -f "$CFG" ] && WORKSPACE_DIR="$(tr -d '\r\357\273\277' < "$CFG" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -n "$WORKSPACE_DIR" ]; then
    echo ""; echo "[+] 删除源码仓库（$WORKSPACE_DIR）..."
    for r in team-standards project-coding-profiles project-domain-knowledge cross-project-topology; do
      d="$WORKSPACE_DIR/$r"; [ -d "$d" ] && rm -rf "$d" && echo "  - 删除 $d"
    done
    echo "  注意：本体 yoooni-daily-plugin 仓未删（脚本在其中）。如需手动删。"
  fi
fi

echo ""; echo "==================== 卸载结果 ===================="
[ -n "$removed_plugins" ] && echo "已卸载插件 :$removed_plugins"
[ -n "$removed_mcp" ] && echo "已移除 MCP :$removed_mcp"
[ -z "$removed_plugins$removed_mcp" ] && echo "没有可卸载项（可能本就没装）。"
echo "重装：scripts/bootstrap-install.sh（全新机器）或 skills/yoooni-install-team-tools/install-team-tools.sh"
echo "插件卸载在重启 Claude Code 会话后完全生效。"
echo "=================================================="
