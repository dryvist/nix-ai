#!/usr/bin/env bash
# Run the fallback-chain probe on a schedule and page when a rung stops
# answering.
#
# WHY THIS EXISTS. litellm-fallback-probe already sends a real completion to
# every rung, and fallback-tier.nix already says it is "the only check that
# settles it" — but nothing ran it. So a converged host could carry a rendered
# config that was entirely correct and a terminal rung that returned 404 to
# every request, and the machine had no opinion about it. That is exactly the
# shape this estate keeps getting caught by: config inspection is a claim,
# a completion is behaviour.
#
# It pages on ABSENCE OF SUCCESS, not on an error being logged somewhere. The
# probe exits non-zero unless EVERY rung serves, and a partial chain is the
# dangerous case: it still serves traffic, so nothing looks wrong until the
# last rung fails too.
#
# EVERY DECISION IS LOGGED, including the no-op. A watcher that is silent when
# it does nothing is indistinguishable from one that never ran.
set -euo pipefail

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
# Indent a captured block for the log. Parameter expansion rather than a sed
# pipe: the linter flags that form (SC2001), and this is one process fewer.
indent() { printf '    %s\n' "${1//$'\n'/$'\n'    }"; }

PROBE="${LITELLM_PROBE_BIN:?litellm-fallback-watch: LITELLM_PROBE_BIN not set}"
ALERT_URL_FILE="${LITELLM_ALERT_URL_FILE:-}"
STATE_DIR="${LITELLM_WATCH_STATE_DIR:-$HOME/Library/Caches/litellm-local}"
# Consecutive failures before paging. One failure is a restart or a model
# reload; the rung being genuinely gone survives several.
CONSECUTIVE="${LITELLM_WATCH_CONSECUTIVE:-2}"
# Re-page interval, so a rung that stays dead does not spam and does not go
# quiet either.
REPAGE_SECONDS="${LITELLM_WATCH_REPAGE_SECONDS:-21600}"

mkdir -p "$STATE_DIR"
STREAK_FILE="$STATE_DIR/fallback-probe-failures"
PAGED_FILE="$STATE_DIR/fallback-probe-last-page"

read_int() { [ -r "$1" ] && tr -cd '0-9' < "$1" | head -c 12 || true; }

alert() {
  local msg="$1"
  if [ -z "$ALERT_URL_FILE" ] || [ ! -s "$ALERT_URL_FILE" ]; then
    echo "$(ts) litellm-fallback-watch: WOULD PAGE but no alert url is seeded: $msg" >&2
    return 0
  fi
  curl -fsS --max-time 20 -X POST -H 'Content-Type: application/json' \
    --data "$(printf '{"text":%s}' "$(printf '%s' "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")" \
    "$(cat "$ALERT_URL_FILE")" >/dev/null \
    && echo "$(ts) litellm-fallback-watch: paged" \
    || echo "$(ts) litellm-fallback-watch: PAGE DELIVERY FAILED" >&2
}

output=$("$PROBE" 2>&1) && rc=0 || rc=$?

if [ "$rc" -eq 0 ]; then
  streak=$(read_int "$STREAK_FILE")
  if [ -n "${streak:-}" ] && [ "${streak:-0}" -gt 0 ] 2>/dev/null; then
    echo "$(ts) litellm-fallback-watch: chain healthy again after ${streak} failed check(s) -> clearing"
  else
    echo "$(ts) litellm-fallback-watch: every rung served a completion -> ok, nothing to do"
  fi
  rm -f "$STREAK_FILE" "$PAGED_FILE"
  exit 0
fi

streak=$(( $(read_int "$STREAK_FILE" || echo 0) + 1 ))
printf '%s\n' "$streak" > "$STREAK_FILE"

if [ "$streak" -lt "$CONSECUTIVE" ]; then
  echo "$(ts) litellm-fallback-watch: probe failed ${streak}/${CONSECUTIVE} (rc=${rc}) -> watching, not paging yet"
  indent "$output"
  exit 0
fi

now=$(date -u +%s)
last=$(read_int "$PAGED_FILE" || echo 0)
last=${last:-0}
if [ "$last" -gt 0 ] && [ $(( now - last )) -lt "$REPAGE_SECONDS" ]; then
  echo "$(ts) litellm-fallback-watch: still failing (streak ${streak}), last page $(( (now - last) / 60 ))m ago -> holding until ${REPAGE_SECONDS}s"
  exit 0
fi

printf '%s\n' "$now" > "$PAGED_FILE"
echo "$(ts) litellm-fallback-watch: WEDGE — probe failed ${streak} consecutive checks (rc=${rc})" >&2
indent "$output" >&2
alert "$(/bin/hostname -s): a local LLM fallback rung stopped serving — the probe failed ${streak} consecutive checks. A rung can 404 while the rendered config stays correct, so inspect with litellm-fallback-probe rather than reading the config. Probe output: ${output}"
exit 1
