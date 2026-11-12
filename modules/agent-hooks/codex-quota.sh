#!/usr/bin/env bash
# Legacy mode exits 0 with quota and 1 otherwise; --json reports quota states.
set -euo pipefail

json_mode=false
if [ "$#" -gt 0 ]; then
  if [ "$#" -eq 1 ] && [ "$1" = "--json" ]; then
    json_mode=true
  else
    echo "usage: codex-quota [--json]" >&2
    exit 2
  fi
fi

exhausted_threshold="${CODEX_QUOTA_EXHAUSTED_THRESHOLD:-95}"
low_threshold="${CODEX_QUOTA_LOW_THRESHOLD:-90}"

unknown() {
  printf '%s\n' '{"state":"unknown","primary":null,"secondary":null}'
  exit 2
}

# A quota reading means nothing when the CLI cannot start. Keep its stderr so
# the caller can see the launch failure (for example, a missing executable).
if ! codex --version >/dev/null; then
  if [ "$json_mode" = true ]; then
    unknown
  fi
  echo "codex-quota: unavailable (the codex CLI does not run)"
  exit 1
fi

sessions="${CODEX_HOME:-$HOME/.codex}/sessions"
now="$(date +%s)"

# Weekly window: a record older than 8 days has reset, so stop looking there.
# The winner is the record with the greatest timestamp across all files, not
# the newest file's last record: a long-running older session keeps its file
# mtime fresh while its last record goes stale.
records="$(find "$sessions" -name 'rollout-*.jsonl' -mtime -8 -exec grep -h '"limit_id":"codex"' {} + 2>/dev/null || true)"
rl="$(jq -nRc '
    [inputs | fromjson? | select(type == "object")
      | {timestamp, limits: (first(.. | objects | select(has("rate_limits")) | .rate_limits))}]
    | map(select(.limits != null and .timestamp != null))
    | sort_by(.timestamp)
    | last | .limits // empty
  ' <<<"$records" 2>/dev/null || true)"

if [ -z "$rl" ]; then
  if [ "$json_mode" = true ]; then
    unknown
  fi
  echo "codex-quota: available (no codex rate_limits record in 8 days)"
  exit 0
fi

if [ "$json_mode" = true ]; then
  result="$(jq -ce \
    --argjson now "$now" \
    --argjson exhausted "$exhausted_threshold" \
    --argjson low "$low_threshold" '
      def valid_window:
        . == null or (
          type == "object"
          and (.used_percent | type == "number")
          and (.resets_at | type == "number")
        );
      def active($window): $window != null and $window.resets_at > $now;
      def state_for($window):
        if (active($window) | not) then "available"
        elif $window.used_percent >= $exhausted then "exhausted"
        elif $window.used_percent >= $low then "low"
        else "available"
        end;
      if ((.primary | valid_window) and (.secondary | valid_window)
          and (.primary != null or .secondary != null)) then
        [.primary, .secondary] as $windows
        | $windows | map(state_for(.)) as $states
        | {
            state: (if ($states | index("exhausted")) != null then "exhausted"
                    elif ($states | index("low")) != null then "low"
                    else "available" end),
            primary: ($windows[0] | if . == null then null else {used_percent, resets_at} end),
            secondary: ($windows[1] | if . == null then null else {used_percent, resets_at} end)
          }
      else error("invalid rate_limits record") end
    ' <<<"$rl" 2>/dev/null)" || unknown
  printf '%s\n' "$result"
  case "$(jq -r '.state' <<<"$result")" in
    available|low) exit 0 ;;
    exhausted) exit 1 ;;
    *) unknown ;;
  esac
fi

if jq -e --argjson now "$now" --argjson exhausted "$exhausted_threshold" \
  '[.primary, .secondary] | map(select(. != null)) | all(.used_percent < $exhausted or .resets_at <= $now)' \
  <<<"$rl" >/dev/null; then
  echo "codex-quota: available $(jq -c '{p: .primary.used_percent, s: .secondary.used_percent}' <<<"$rl")"
  exit 0
fi
echo "codex-quota: exhausted $(jq -c '{p: .primary.used_percent, s: .secondary.used_percent, resets_at: .primary.resets_at}' <<<"$rl")"
exit 1
