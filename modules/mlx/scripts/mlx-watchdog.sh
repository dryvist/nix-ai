#!/usr/bin/env bash
# mlx-watchdog - self-heal a serving host that is up but not serving.
#
# KeepAlive=true only restarts the proxy on process EXIT, so every failure that
# leaves a live-but-useless proxy is invisible to launchd. Three such modes have
# been observed on this host, and NONE of them show at /v1/models:
#
#   1. llama-swap panics into a listening-but-dead zombie (socket open, answers
#      nothing) -> connection refused / hung streams.
#   2. The vllm-mlx batch scheduler wedges and then answers EVERY completion with
#      HTTP 200, finish_reason "error" and zero tokens. litellm even remaps that
#      finish_reason to "stop" downstream, so it looks like a normal answer.
#   3. An orphaned worker holds the engine port, so each fresh worker dies on
#      bind and the proxy 429s every completion (fixed at the source by
#      llama-swap-launch.sh, which reaps orphans before the proxy starts).
#
# /v1/models is answered by llama-swap itself from static config, without a
# model, so it returned 200 throughout all three - including a ~1.5 h total
# outage. It cannot be the health signal. The only thing that separates "serving"
# from merely "up" is a real completion that yields a token, so that is what this
# probes. Cost is one <=4-token generation per StartInterval against an
# already-resident model - cheap next to another silent multi-hour outage.
# See Zammad (AI/LLM Serving).
#
# Loop-cadence (durable min-interval marker): the scheduler is launchd's
# StartInterval, but a 70 GB model reload takes 20-60 s, so a naive probe would
# see "still down" and kickstart again mid-reload, never recovering. A cooldown
# marker written AFTER each kickstart gates re-firing: a storming scheduler
# no-ops, a genuinely-still-dead proxy is retried only once the cooldown lapses.

set -euo pipefail

api_url="${MLX_API_URL:?MLX_API_URL unset}"
label="${MLX_LAUNCHD_LABEL:?MLX_LAUNCHD_LABEL unset}"
probe_model="${MLX_WATCHDOG_PROBE_MODEL:?MLX_WATCHDOG_PROBE_MODEL unset}"
marker="${MLX_WATCHDOG_MARKER:-${HOME}/Library/Caches/vllm-mlx/watchdog-last-kick}"
# Cooldown covers ThrottleInterval (120 s) plus a full cold load of the largest
# resident model, so one kickstart gets a real recovery window before the next.
cooldown="${MLX_WATCHDOG_COOLDOWN:-600}"
# A cold load legitimately holds a completion open for minutes; a short timeout
# turns every normal model swap into a false positive.
probe_timeout="${MLX_WATCHDOG_PROBE_TIMEOUT:-240}"

mkdir -p "$(dirname "$marker")"

# Cadence gate FIRST: if we kickstarted within the cooldown, the proxy may still
# be reloading - do nothing (including no log noise) rather than re-kick it.
now="$(date +%s)"
last="$(cat "$marker" 2>/dev/null || echo 0)"
# A corrupt/partial marker write (non-integer content) would crash the
# arithmetic below under set -e ("value too great for base"); an empty file is
# already treated as 0 by (( )). Coerce anything non-numeric back to 0.
[[ "$last" =~ ^[0-9]+$ ]] || last=0
if (( now - last < cooldown )); then
  exit 0
fi

# Healthy iff the response carries at least one generated token. HTTP status and
# finish_reason are both untrustworthy here (mode 2 above), so completion_tokens
# is the only assertion worth making.
probe() {
  local request body
  # Build the body with jq so a model id carrying quotes/backslashes cannot
  # produce invalid JSON — that would fail the probe for a reason unrelated to
  # serving health and kickstart a perfectly good proxy.
  request="$(jq -nc --arg model "$probe_model" \
    '{model: $model, messages: [{role: "user", content: "ping"}], max_tokens: 4}')" || return 1
  body="$(curl -s --max-time "$probe_timeout" \
    -H 'Content-Type: application/json' \
    -d "$request" \
    "${api_url}/chat/completions" 2>/dev/null)" || return 1
  jq -e '(.usage.completion_tokens // 0) >= 1' >/dev/null 2>&1 <<<"$body"
}

# One transient miss (a hiccup under load, or a swap-in) must not trigger a
# restart, so require two consecutive failures.
if probe; then
  exit 0
fi
sleep 5
if probe; then
  exit 0
fi

# Confirmed not serving. launchctl is a system binary (absolute path - not on the
# sanitized writeShellApplication PATH). `id` comes from coreutils. The kickstart
# is a real remedy only because llama-swap-launch.sh reaps orphaned workers on
# the way back up; without that, mode 3 restart-loops forever.
echo "$(date -u +%FT%TZ) mlx-watchdog: ${probe_model} produced no tokens x2 -> kickstart ${label}" >&2
/bin/launchctl kickstart -k "gui/$(id -u)/${label}" || true

# Marker written AFTER the work: a crashed run does not suppress the retry; only
# a successful kickstart starts the cooldown.
printf '%s\n' "$now" > "$marker"
