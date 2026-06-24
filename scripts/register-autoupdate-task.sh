#!/usr/bin/env bash
# register-autoupdate-task.sh —— macOS launchd 计划任务：每 N 小时自动刷新公司套件（会话外也刷新）。
# 对照 register-autoupdate-task.ps1（Windows schtasks）。用户级 LaunchAgent，无需管理员。
# 关键：任务指向【稳定启动器】~/.kai-toolbox/run-update.sh（非版本化的 update-team-tools.sh），
# 启动器运行时再定位最新版脚本。"开 Claude Code 即刷新" 由 SessionStart hook 负责，二者互补。
# --only-if-exists：自愈模式，仅当 plist 已存在才校准；从未注册过则什么都不做。
# 用法: bash register-autoupdate-task.sh [--every-hours 4] [--only-if-exists]
set -u
EVERY_HOURS=4
ONLY_IF_EXISTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --every-hours) EVERY_HOURS="${2:-4}"; shift 2 ;;
    --only-if-exists) ONLY_IF_EXISTS=1; shift ;;
    *) shift ;;
  esac
done

# 仅 macOS 有 launchd；其它（如 Linux）建议用 cron，本脚本不处理
if [ "$(uname -s)" != "Darwin" ]; then
  echo "register-autoupdate-task.sh 仅支持 macOS(launchd)；Linux 请用 cron 调 ~/.kai-toolbox/run-update.sh。" >&2
  exit 0
fi

LABEL="com.yoooni.team-tools-autoupdate"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "$ONLY_IF_EXISTS" = "1" ] && [ ! -f "$PLIST" ]; then
  exit 0   # 自愈：从未注册过就不创建
fi

STATE_DIR="$HOME/.kai-toolbox"
mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents"
LAUNCHER="$STATE_DIR/run-update.sh"

# 部署/刷新稳定启动器到固定路径 + 记下源脚本作回退（每次都做以保持最新）
SRC_LAUNCHER="$(cd "$(dirname "$0")" && pwd)/run-update.sh"
[ -f "$SRC_LAUNCHER" ] && cp -f "$SRC_LAUNCHER" "$LAUNCHER" && chmod +x "$LAUNCHER"
printf '%s' "$(cd "$(dirname "$0")" && pwd)/update-team-tools.sh" > "$STATE_DIR/update-script.path"

INTERVAL=$(( EVERY_HOURS * 3600 ))
# 写 plist：登录 shell(-lc) 跑启动器，确保 PATH 含 node/npm/claude（nvm/homebrew）
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>"\$HOME/.kai-toolbox/run-update.sh"</string>
  </array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$STATE_DIR/team-tools-autoupdate.out</string>
  <key>StandardErrorPath</key><string>$STATE_DIR/team-tools-autoupdate.err</string>
</dict>
</plist>
EOF

# 重新加载（先 unload 旧的，忽略报错；再 load）
launchctl unload "$PLIST" >/dev/null 2>&1 || true
if launchctl load "$PLIST" >/dev/null 2>&1; then
  echo "已注册 launchd 任务 '$LABEL'（每 $EVERY_HOURS 小时）-> $LAUNCHER"
else
  echo "launchctl load 失败，请在自己的终端手动执行：launchctl load \"$PLIST\"" >&2
fi
