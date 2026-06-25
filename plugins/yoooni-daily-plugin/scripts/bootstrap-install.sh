#!/usr/bin/env bash
# PATH self-heal (macOS): Finder double-click runs with a minimal PATH that often omits
# node / npm-global (where claude lives), so installed tools look missing. Prepend common
# Homebrew + npm-global bins (harmless if a dir is absent). Mirrors the Windows .cmd fix.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin:$PATH"
# bootstrap-install.sh —— macOS/Linux「全新机器一键引导安装」（Gitee 源），对照 bootstrap-install.ps1。
# 比 install-team-tools.sh 多做两件：(1) 克隆+安装本体 yoooni-daily-plugin；(2) 注册定时自动更新(launchd)。
# 中间「关联插件 + MCP」委托 install-team-tools.sh（幂等、已装跳过）。
# 用法: bash bootstrap-install.sh [-w <workspaceDir>] [-s user|local|project] [--every-hours 4]
set -u
WORKSPACE_DIR=""; SCOPE="user"; EVERY_HOURS=4; GITEE="https://gitee.com/wyoooni"
while [ $# -gt 0 ]; do
  case "$1" in
    -w|--workspace) WORKSPACE_DIR="${2:-}"; shift 2 ;;
    -s|--scope) SCOPE="${2:-user}"; shift 2 ;;
    --every-hours) EVERY_HOURS="${2:-4}"; shift 2 ;;
    *) shift ;;
  esac
done
has() { command -v "$1" >/dev/null 2>&1; }
STATE_DIR="$HOME/.kai-toolbox"; mkdir -p "$STATE_DIR"; CFG="$STATE_DIR/workspace.path"

has git || { echo "Git 是必需项，请先安装：https://git-scm.com/download/mac 或 brew install git" >&2; exit 1; }
has node && has npm || echo "[warn] 未检测到 node/npm(>=18)，MCP 构建会被跳过：https://nodejs.org 或 brew install node"
has claude && HAS_CLAUDE=1 || { HAS_CLAUDE=0; echo "[warn] 未检测到 claude CLI，插件/MCP 安装会被跳过：npm install -g @anthropic-ai/claude-code"; }

has_self() { [ -n "$1" ] && [ -d "$1/yoooni-daily-plugin/.git" ]; }
resolved=""
for c in "$WORKSPACE_DIR" "${YOOONI_WORKSPACE_DIR:-}" "$([ -f "$CFG" ] && tr -d '\r\357\273\277' < "$CFG" | head -n1)" "$HOME/myWork"; do
  [ -n "$c" ] || continue; if has_self "$c"; then resolved="$c"; break; fi
done
[ -z "$resolved" ] && resolved="${WORKSPACE_DIR:-$([ -f "$CFG" ] && tr -d '\r\357\273\277' < "$CFG" | head -n1 || echo "$HOME/myWork")}"
WORKSPACE_DIR="$resolved"; printf '%s' "$WORKSPACE_DIR" > "$CFG"; mkdir -p "$WORKSPACE_DIR"

echo "=================================================="
echo " 公司团队套件【全新机器一键引导】(Gitee 源)"
echo "=================================================="
echo "工作区目录: $WORKSPACE_DIR ; 安装范围: $SCOPE ; 定时更新: 每 $EVERY_HOURS 小时"

# --- 1) 本体 yoooni-daily-plugin：克隆 + 安装插件 ---
self="yoooni-daily-plugin"; self_dir="$WORKSPACE_DIR/$self"; self_url="$GITEE/$self.git"; self_ref="${self}@${self}"
echo ""; echo "[1/3] 本体 $self（克隆 + 安装插件）..."
if [ -d "$self_dir/.git" ]; then echo "  = 仓库已存在，跳过克隆"; else echo "  + git clone $self_url"; git clone "$self_url" "$self_dir"; fi
if [ "$HAS_CLAUDE" = "1" ]; then
  if claude plugin list 2>/dev/null | grep -qF "$self_ref"; then echo "  = 插件已安装，跳过: $self_ref"
  else
    claude plugin marketplace list 2>/dev/null | grep -qF "$self" || { echo "  + marketplace add $self_url"; claude plugin marketplace add "$self_url"; }
    echo "  + plugin install $self_ref"; claude plugin install "$self_ref" -s "$SCOPE"
  fi
fi

# --- 2) 关联插件 + MCP：委托 install-team-tools.sh ---
echo ""; echo "[2/3] 关联插件 + MCP（委托 install-team-tools.sh）..."
installer="$self_dir/skills/yoooni-install-team-tools/install-team-tools.sh"
if [ -f "$installer" ]; then bash "$installer" -w "$WORKSPACE_DIR" -s "$SCOPE"
else echo "  [warn] 未找到 $installer（本体克隆可能失败），检查网络后重跑。"; fi

# --- 3) 注册定时自动更新（launchd，仅 macOS）---
echo ""; echo "[3/3] 注册定时自动更新任务..."
register="$self_dir/scripts/register-autoupdate-task.sh"
if [ "$EVERY_HOURS" -le 0 ]; then echo "  (every-hours<=0，跳过)"
elif [ "$(uname -s)" != "Darwin" ]; then echo "  (非 macOS，跳过 launchd；Linux 请用 cron 调 ~/.kai-toolbox/run-update.sh)"
elif [ -f "$register" ]; then bash "$register" --every-hours "$EVERY_HOURS"
else echo "  [warn] 未找到 $register，跳过。"; fi

echo ""; echo "================== 引导完成 =================="
echo "插件安装后需【重启 Claude Code 会话】生效。"
echo "保持最新：launchd 每 $EVERY_HOURS 小时自动跑；开 Claude Code 会话也会触发 SessionStart 刷新。"
echo "=================================================="
