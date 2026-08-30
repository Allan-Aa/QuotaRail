#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
./build-app.sh

source_app="$(pwd)/dist/QuotaRail.app"
destination="/Applications/QuotaRail.app"
trash_directory="$HOME/.Trash"

if [[ ! -w "/Applications" ]]; then
  echo "Cannot install to /Applications without write permission. Re-run from an administrator-approved terminal."
  exit 1
fi

expected_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist")
staging_root=$(mktemp -d "/Applications/.QuotaRail-install.XXXXXX")
staged_app="$staging_root/QuotaRail.app"
backup_path=""
install_verified=false

rollback_if_needed() {
  local status=$?
  if [[ "$install_verified" != true && -n "$backup_path" && -d "$backup_path" ]]; then
    if [[ -d "$destination" ]]; then
      failed_path="$trash_directory/QuotaRail-${expected_version}-failed-$(date +%Y%m%d-%H%M%S)-$$.app"
      mv "$destination" "$failed_path" 2>/dev/null || true
    fi
    mv "$backup_path" "$destination" 2>/dev/null || true
    echo "Upgrade did not complete; restored the previous app from backup."
  fi
  [[ -n "${staging_root:-}" && -d "$staging_root" ]] && rm -rf "$staging_root"
  exit "$status"
}
trap rollback_if_needed EXIT

ditto "$source_app" "$staged_app"
plutil -lint "$staged_app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$staged_app"
[[ -x "$staged_app/Contents/MacOS/QuotaRail" ]]
[[ "$expected_version" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staged_app/Contents/Info.plist")" ]]

old_pids=$(pgrep -f "^${destination}/Contents/MacOS/QuotaRail$" || true)
if [[ -n "$old_pids" ]]; then
  while IFS= read -r pid; do kill -TERM "$pid"; done <<< "$old_pids"
  for _ in {1..50}; do
    [[ -z "$(pgrep -f "^${destination}/Contents/MacOS/QuotaRail$" || true)" ]] && break
    sleep 0.1
  done
  if [[ -n "$(pgrep -f "^${destination}/Contents/MacOS/QuotaRail$" || true)" ]]; then
    echo "QuotaRail is still running; installation stopped without replacing the existing app."
    exit 1
  fi
fi

if [[ -d "$destination" ]]; then
  mkdir -p "$trash_directory"
  previous_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist" 2>/dev/null || echo unknown)
  backup_path="$trash_directory/QuotaRail-${previous_version}-backup-$(date +%Y%m%d-%H%M%S)-$$.app"
  mv "$destination" "$backup_path"
fi

mv "$staged_app" "$destination"
codesign --verify --deep --strict --verbose=2 "$destination"
installed_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist")
[[ "$installed_version" == "$expected_version" ]]

open "$destination"
running_pid=""
for _ in {1..50}; do
  running_pid=$(pgrep -f "^${destination}/Contents/MacOS/QuotaRail$" | head -n 1 || true)
  [[ -n "$running_pid" ]] && break
  sleep 0.1
done
if [[ -z "$running_pid" ]]; then
  echo "Installed version $installed_version, but the new app did not start; restoring the backup."
  exit 1
fi
running_path=$(ps -p "$running_pid" -o command= | sed 's/^[[:space:]]*//')
[[ "$running_path" == "$destination/Contents/MacOS/QuotaRail" ]]

install_verified=true

echo "Installed $destination (version $installed_version, pid $running_pid, running $running_path)"
if [[ -n "$backup_path" ]]; then
  echo "Previous version backed up to $backup_path"
fi
