#!/usr/bin/env bash
# Exit 0 when Codex has quota: every window in the newest limit_id=codex
# rate_limits record is under 90% used or already reset. Exit 1 otherwise.
set -euo pipefail

sessions="${CODEX_HOME:-$HOME/.codex}/sessions"
now="$(date +%s)"
rl=""

# Weekly window: a record older than 8 days has reset, so stop looking there.
while IFS= read -r f; do
  rl="$(grep -h '"limit_id":"codex"' "$f" | tail -1 |
    jq -c 'first(.. | objects | select(has("rate_limits")) | .rate_limits)' 2>/dev/null || true)"
  [ -n "$rl" ] && break
done < <(find "$sessions" -name 'rollout-*.jsonl' -mtime -8 -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null)

if [ -z "$rl" ]; then
  echo "codex-quota: available (no codex rate_limits record in 8 days)"
  exit 0
fi

if jq -e --argjson now "$now" \
  '[.primary, .secondary] | map(select(. != null)) | all(.used_percent < 90 or .resets_at <= $now)' \
  <<<"$rl" >/dev/null; then
  echo "codex-quota: available $(jq -c '{p: .primary.used_percent, s: .secondary.used_percent}' <<<"$rl")"
  exit 0
fi
echo "codex-quota: exhausted $(jq -c '{p: .primary.used_percent, s: .secondary.used_percent, resets_at: .primary.resets_at}' <<<"$rl")"
exit 1
