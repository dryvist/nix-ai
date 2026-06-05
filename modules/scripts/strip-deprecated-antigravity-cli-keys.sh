#!/usr/bin/env bash
# Strip deprecated tools.allowed and tools.exclude from Antigravity CLI settings.json.
# Called by home.activation after merge-json-settings.sh deep-merges runtime state.
# The deep-merge preserves old keys; this script removes them post-merge.
# umask 077 + chmod 600 ensure auth tokens stay protected.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: strip-deprecated-antigravity-cli-keys <settings-path>" >&2
  exit 1
fi

SETTINGS="$1"

if [[ ! -f "$SETTINGS" ]]; then
  exit 0
fi

umask 077
jq 'del(.tools.allowed, .tools.exclude)' "$SETTINGS" > "$SETTINGS.tmp" \
  && mv "$SETTINGS.tmp" "$SETTINGS" \
  && chmod 600 "$SETTINGS"
