#!/usr/bin/env bash
# team-tools-install.command —— macOS 可双击的一键安装包装器（对照 team-tools-install.cmd）。
# 双击前请确保已装 Git / Node.js(>=18) / Claude Code CLI。首次会提示 Gitee 登录（之后缓存）。
# 若双击报「无法打开，因为来自身份不明的开发者」：右键→打开，或先 chmod +x 本文件。
cd "$(dirname "$0")" || exit 1
echo "=================================================="
echo "        公司团队工具 · 一键安装 (macOS)"
echo "  需要：Git（必需）· Node.js 18+ · Claude Code CLI"
echo "=================================================="
echo ""
if [ ! -f "./bootstrap-install.sh" ]; then
  echo "[错误] 同目录缺少 bootstrap-install.sh，无法安装。" >&2
  read -r -p "按回车关闭..." _; exit 1
fi
command -v git >/dev/null 2>&1 || echo "[提示] 未检测到 git：https://git-scm.com/download/mac 或 brew install git"
bash "./bootstrap-install.sh"
echo ""
echo "安装流程结束。重启 Claude Code 会话后插件生效。"
read -r -p "按回车关闭此窗口..." _
