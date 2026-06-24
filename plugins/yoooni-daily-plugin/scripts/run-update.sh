#!/usr/bin/env bash
# run-update.sh —— macOS/Linux 稳定启动器（路径永不变），对照 run-update.ps1。
# launchd 计划任务固定指向 ~/.kai-toolbox/run-update.sh，运行时再定位「当前最新版」插件里的
# update-team-tools.sh 调用它（插件缓存目录带版本号，自更新后旧目录被回收，写死路径会断）。
# 定位顺序：缓存里最高版本 > 回退路径(注册时记下的源脚本)。
set -u
STATE_DIR="$HOME/.kai-toolbox"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/team-tools-update.log"
log() { printf '[%s] launcher: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

target=""
cache_root="$HOME/.claude/plugins/cache/yoooni-daily-plugin/yoooni-daily-plugin"
if [ -d "$cache_root" ]; then
  # 取版本号最高且含 scripts/update-team-tools.sh 的目录（版本号排序用 sort -V）
  best=""
  for d in "$cache_root"/*/; do
    [ -f "${d}scripts/update-team-tools.sh" ] || continue
    name="$(basename "$d")"
    ver="$(printf '%s' "$name" | grep -oE '^[0-9]+(\.[0-9]+)*' | head -n1)"
    [ -z "$ver" ] && continue
    if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "$best" "$ver" | sort -V | tail -n1)" = "$ver" ]; then
      best="$ver"; target="${d}scripts/update-team-tools.sh"
    fi
  done
fi
if [ -z "$target" ]; then
  fb="$STATE_DIR/update-script.path"
  if [ -f "$fb" ]; then
    p="$(tr -d '\r\357\273\277' < "$fb" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$p" ] && [ -f "$p" ] && target="$p"
  fi
fi

if [ -n "$target" ]; then
  log "-> $target"
  bash "$target"
else
  log "未找到 update-team-tools.sh（缓存与回退路径均无）"
fi
