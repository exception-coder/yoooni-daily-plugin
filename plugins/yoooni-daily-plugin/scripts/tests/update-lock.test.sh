#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../update-lock.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/yoooni-update-lock-test.XXXXXX")"
cleanup() {
  release_yoooni_update_lock
  rm -f "$test_root/team-tools-update.lock/pid" 2>/dev/null || true
  rmdir "$test_root/team-tools-update.lock" 2>/dev/null || true
  rmdir "$test_root" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

acquire_yoooni_update_lock "$test_root" || { echo 'first lock acquisition failed' >&2; exit 1; }
if acquire_yoooni_update_lock "$test_root"; then
  echo 'active lock was incorrectly replaced' >&2
  exit 1
fi
release_yoooni_update_lock

mkdir "$test_root/team-tools-update.lock"
printf '%s\n' '99999999' > "$test_root/team-tools-update.lock/pid"
acquire_yoooni_update_lock "$test_root" || { echo 'stale lock was not recovered' >&2; exit 1; }
release_yoooni_update_lock

mkdir "$test_root/team-tools-update.lock"
printf '%s\n' '-1' > "$test_root/team-tools-update.lock/pid"
acquire_yoooni_update_lock "$test_root" || { echo 'invalid PID lock was not recovered' >&2; exit 1; }
release_yoooni_update_lock

echo 'update lock tests passed'
