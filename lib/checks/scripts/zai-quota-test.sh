#!/usr/bin/env bash
set -euo pipefail

script="${SRC:?}/modules/agent-hooks/zai-quota.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export ZAI_QUOTA_MARKER="$tmp/unavailable-until"

bash "$script"

printf '%s\n' 9999999999 >"$ZAI_QUOTA_MARKER"
if bash "$script"; then
  printf '%s\n' 'active quota marker was ignored' >&2
  exit 1
fi

printf '%s\n' 1 >"$ZAI_QUOTA_MARKER"
bash "$script"

printf '%s\n' invalid >"$ZAI_QUOTA_MARKER"
if bash "$script"; then
  printf '%s\n' 'malformed quota marker was ignored' >&2
  exit 1
fi

printf '%s\n' 'zai-quota: marker expiry cases behave as expected'
