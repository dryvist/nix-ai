#!/usr/bin/env bash
set -euo pipefail

home_dir=$1
runtime="$home_dir/Library/Application Support/Token Meter/runtime/"

cleanup_agent() {
  local label=$1
  local plist="$home_dir/Library/LaunchAgents/$label.plist"

  [[ -f "$plist" ]] || return 0
  grep -Fq "$runtime" "$plist" || return 0
  launchctl bootout "gui/$UID/$label" >/dev/null 2>&1 || true
  rm -f "$plist"
}

cleanup_agent com.token-meter.server
cleanup_agent com.token-meter.menubar
