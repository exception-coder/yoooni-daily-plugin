#!/usr/bin/env bash
# team-tools-uninstall.command —— macOS 可双击的一键卸载包装器（对照 team-tools-uninstall.cmd）。
# 只摘除本套件的插件 / MCP / launchd 任务；默认保留源码仓与 marketplace 登记。
cd "$(dirname "$0")" || exit 1
echo "=================================================="
echo "        公司团队套件 · 一键卸载 (macOS)"
echo "  将移除：3 插件 + 2 MCP + launchd 定时任务"
echo "  默认保留：克隆的源码仓、marketplace 登记"
echo "=================================================="
echo ""
if [ ! -f "./uninstall-team-tools.sh" ]; then
  echo "[错误] 同目录缺少 uninstall-team-tools.sh。" >&2
  read -r -p "按回车关闭..." _; exit 1
fi
read -r -p "按回车确认卸载，或直接关闭窗口取消..." _
bash "./uninstall-team-tools.sh"
echo ""
echo "卸载流程结束。重启 Claude Code 会话后完全生效。"
read -r -p "按回车关闭此窗口..." _
