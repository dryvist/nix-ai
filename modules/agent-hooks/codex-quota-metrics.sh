#!/usr/bin/env bash
# Prints the Codex quota reading as Prometheus exposition on stdout, for
# agent-quota-push. Exits 1 with nothing on stdout when there is no usable
# record or a window's fields are malformed; the reason goes to stderr.
# codex_rollout_record comes from codex-rollouts.sh, inlined ahead of this body.
set -euo pipefail

now="$(date +%s)"
host="$(hostname -s)"
record="$(codex_rollout_record)"
if [ -z "$record" ]; then
  echo "codex-quota-metrics: no codex rate_limits record in the last 8 days" >&2
  exit 1
fi

# window_minutes 300 is the 5h window and 10080 the weekly one; other windows
# are skipped. A window with a non-numeric field, or a record with no window,
# is malformed. A window whose reset has passed is omitted.
# The exposition is built in a variable so a malformed second window cannot
# leave half of the output on stdout.
if ! lines="$(jq -r --argjson now "$now" --arg host "$host" '
  def window_label: if . == 300 then "5h" elif . == 10080 then "weekly" else null end;
  . as $r
  | ($r.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $ts
  | ([$r.limits.primary, $r.limits.secondary] | map(select(. != null))) as $windows
  | (if ($windows | length) == 0 then error("no primary or secondary window") else $windows end)[]
  | if ([.used_percent, .window_minutes, .resets_at] | all(type == "number"))
    then . else error("malformed window") end
  | (.window_minutes | window_label) as $w
  | select($w != null and .resets_at > $now)
  | "executor=\"codex\",window=\"\($w)\",source=\"rollout_record\",host=\"\($host)\"" as $l
  | "agent_quota_used_percent{\($l)} \(.used_percent)",
    "agent_quota_window_seconds{\($l)} \(.window_minutes * 60)",
    "agent_quota_reset_timestamp_seconds{\($l)} \(.resets_at)",
    "agent_quota_reading_timestamp_seconds{\($l)} \($ts)"
' <<<"$record")"; then
  echo "codex-quota-metrics: malformed codex rate_limits record; nothing printed" >&2
  exit 1
fi

if [ -n "$lines" ]; then
  printf '%s\n' "$lines"
fi
# Heartbeat: written only on a successful read, so a stale value means the probe has not succeeded.
printf 'agent_quota_probe_last_success_timestamp_seconds{executor="codex",host="%s"} %s\n' "$host" "$now"
