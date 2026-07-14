#!/usr/bin/env bash
# mlx-watchdog - self-heal the listening-but-dead llama-swap zombie.
#
# The vllm-mlx LaunchAgent uses KeepAlive=true, which only restarts the proxy on
# process EXIT. But llama-swap can panic (`sync: WaitGroup is reused before
# previous Wait has returned`) into a process that is still ALIVE and still
# holding the listen socket, yet answers nothing - a zombie. launchd never
# notices (no exit), so the socket stays open, every request gets
# connection-refused / a hung stream, and litellm surfaces
# MidStreamFallbackError until a human kickstarts it. This probe closes that gap:
# it health-checks the proxy's own /v1/models endpoint and, on repeated failure,
# kickstarts the server LaunchAgent - the sanctioned Mac serving-host break-fix.
#
# Health signal choice: /v1/models is answered by llama-swap itself from its
# static config, WITHOUT loading a model, so it stays up during a normal model
# swap. A failure there means the proxy - not a worker - is dead. That is the
# exact zombie signature, and it avoids the cost/side-effects of a real
# completion probe.
#
# Loop-cadence (durable min-interval marker): the scheduler is launchd's
# StartInterval, but a 70 GB model reload takes 20-60 s, so a naive probe would
# see "still down" and kickstart again mid-reload, never recovering. A cooldown
# marker written AFTER each kickstart gates re-firing: a storming scheduler
# no-ops, a genuinely-still-dead proxy is retried only once the cooldown lapses.

set -euo pipefail

health_url="${MLX_API_URL:?MLX_API_URL unset}/models"
label="${MLX_LAUNCHD_LABEL:?MLX_LAUNCHD_LABEL unset}"
marker="${MLX_WATCHDOG_MARKER:-${HOME}/Library/Caches/vllm-mlx/watchdog-last-kick}"
# Cooldown >= ThrottleInterval (120 s) + headroom for the largest resident
# model's cold load, so one kickstart gets a full recovery window before the
# next is allowed.
cooldown="${MLX_WATCHDOG_COOLDOWN:-180}"
probe_timeout="${MLX_WATCHDOG_PROBE_TIMEOUT:-15}"

mkdir -p "$(dirname "$marker")"

# Cadence gate FIRST: if we kickstarted within the cooldown, the proxy may still
# be reloading - do nothing (including no log noise) rather than re-kick it.
now="$(date +%s)"
last="$(cat "$marker" 2>/dev/null || echo 0)"
if (( now - last < cooldown )); then
  exit 0
fi

probe() { curl -sf --max-time "$probe_timeout" "$health_url" >/dev/null 2>&1; }

# Healthy proxy answers immediately. One transient miss (a brief hiccup under
# load) must not trigger a restart, so require two consecutive failures.
if probe; then
  exit 0
fi
sleep 3
if probe; then
  exit 0
fi

# Zombie confirmed. launchctl is a system binary (absolute path - not on the
# sanitized writeShellApplication PATH). `id` comes from coreutils.
echo "$(date -u +%FT%TZ) mlx-watchdog: ${health_url} unreachable x2 -> kickstart ${label}" >&2
/bin/launchctl kickstart -k "gui/$(id -u)/${label}" || true

# Marker written AFTER the work: a crashed run does not suppress the retry; only
# a successful kickstart starts the cooldown.
printf '%s\n' "$now" > "$marker"
