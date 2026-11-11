#!/usr/bin/env bash
# Exit 0 when the codex CLI runs and Codex has quota. Exit 1 otherwise.
set -euo pipefail

# A quota reading means nothing when the CLI cannot start; the launcher exits 127 when its target is missing.
if ! codex --version >/dev/null 2>&1; then
  echo "codex-quota: unavailable (the codex CLI does not run)"
  exit 1
fi

now="$(date +%s)"

rl="$(codex_rollout_record | jq -c '.limits // empty' 2>/dev/null || true)"

if [ -z "$rl" ]; then
  echo "codex-quota: available (no codex rate_limits record in 8 days)"
  exit 0
fi

if jq -e --argjson now "$now" \
  '[.primary, .secondary] | map(select(. != null)) | all(.used_percent < 95 or .resets_at <= $now)' \
  <<<"$rl" >/dev/null; then
  echo "codex-quota: available $(jq -c '{p: .primary.used_percent, s: .secondary.used_percent}' <<<"$rl")"
  exit 0
fi
echo "codex-quota: exhausted $(jq -c '{p: .primary.used_percent, s: .secondary.used_percent, resets_at: .primary.resets_at}' <<<"$rl")"
exit 1
