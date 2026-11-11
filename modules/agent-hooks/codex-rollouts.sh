#!/usr/bin/env bash
# Shared by codex-quota and codex-quota-metrics. default.nix inlines this file
# ahead of each consumer's body (builtins.readFile), so it has no runtime path
# of its own and is not executable alone.
#
# codex_rollout_record prints the winning rate-limit record as one line,
# {"timestamp": ..., "limits": {...}}: the greatest timestamp across rollout
# files modified in the last 8 days that carry "limit_id":"codex". It prints
# nothing when there is no such record or the selection fails; each caller
# decides what that means.
codex_rollout_record() {
  local sessions="${CODEX_HOME:-$HOME/.codex}/sessions"
  # Weekly window: a record older than 8 days has reset, so stop looking there.
  # The winner is the record with the greatest timestamp across all files, not
  # the newest file's last record: a long-running older session keeps its file
  # mtime fresh while its last record goes stale.
  find "$sessions" -name 'rollout-*.jsonl' -mtime -8 -exec grep -h '"limit_id":"codex"' {} + 2>/dev/null |
    jq -nRc '
      [inputs | fromjson? | select(type == "object")
        | {timestamp, limits: (first(.. | objects | select(has("rate_limits")) | .rate_limits))}]
      | map(select(.limits != null and .timestamp != null))
      | sort_by(.timestamp)
      | last // empty
    ' 2>/dev/null || true
}
