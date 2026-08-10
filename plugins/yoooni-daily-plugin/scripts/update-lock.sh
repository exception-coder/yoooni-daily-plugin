#!/usr/bin/env bash

acquire_yoooni_update_lock() {
  state_dir="$1"
  lock_dir="$state_dir/team-tools-update.lock"
  mkdir -p "$state_dir"

  if ! mkdir "$lock_dir" 2>/dev/null; then
    lock_pid=""
    [ -f "$lock_dir/pid" ] && IFS= read -r lock_pid < "$lock_dir/pid"
    case "$lock_pid" in
      ''|*[!0-9]*) lock_pid="" ;;
    esac
    if [ -n "$lock_pid" ] && [ "$lock_pid" -gt 1 ] && kill -0 "$lock_pid" 2>/dev/null; then
      return 1
    fi
    rm -f "$lock_dir/pid" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || return 1
    mkdir "$lock_dir" 2>/dev/null || return 1
  fi

  printf '%s\n' "$$" > "$lock_dir/pid"
  YOOONI_UPDATE_LOCK_DIR="$lock_dir"
  export YOOONI_UPDATE_LOCK_DIR
  return 0
}

release_yoooni_update_lock() {
  lock_dir="${YOOONI_UPDATE_LOCK_DIR:-}"
  [ -n "$lock_dir" ] || return 0
  owner_pid=""
  [ -f "$lock_dir/pid" ] && IFS= read -r owner_pid < "$lock_dir/pid"
  if [ "$owner_pid" = "$$" ]; then
    rm -f "$lock_dir/pid" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  YOOONI_UPDATE_LOCK_DIR=""
}
