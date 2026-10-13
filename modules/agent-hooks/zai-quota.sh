#!/usr/bin/env bash
set -euo pipefail

marker="${ZAI_QUOTA_MARKER:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-route/zai-quota-until}"
[ -e "$marker" ] || exit 0

if ! IFS= read -r unavailable_until <"$marker" || [[ ! $unavailable_until =~ ^[0-9]{1,10}$ ]]; then
  exit 1
fi

if (( unavailable_until > $(date +%s) )); then
  exit 1
fi

exit 0
