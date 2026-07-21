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
# See Zammad: AI/LLM Serving INC-17114.
#
# Escalation ladder (a single `kickstart -k` is NOT always a remedy):
#   - `launchctl kickstart` cannot clear a launchd-THROTTLED unit
#     (ThrottleInterval=120) nor a slot-starved one, and its own launchctl child
#     died `Terminated: 15` when the uid hit kern.maxprocperuid — the healer
#     starved with the patient. So failures escalate by a persisted counter:
#       failure 1 : reap orphan `vllm-mlx serve` workers, then `kickstart -k`.
#       failure 2+: full teardown — `bootout` the agent, SIGKILL any surviving
#                   worker/proxy orphans, then `bootstrap` the plist (retry
#                   loop) and `kickstart` to start now. This is the only path
#                   that clears a throttled/slot-starved unit.
#   - Entering the teardown stage fires an ntfy alert if the untracked url file
#     exists (mirrors cluster-link-watcher.sh; missing file = no page).
#   - A successful two-probe pass resets the counter and cooldown.
#
# Fork-exhaustion awareness: kern.maxprocperuid exhaustion (orphan worker trees
# re-parented to init holding process-table slots, plus a flood of failed
# `/bin/sh` forks) is what killed the healer on 2026-07-20. Every tick records
# the uid's process count; above a threshold it reaps orphan worker trees to
# reclaim slots before the box can no longer fork at all.
#
# Loop-cadence (durable min-interval marker): the scheduler is launchd's
# StartInterval, but a model reload takes 20-60 s, so a naive probe would see
# "still down" and remediate again mid-reload, never recovering. A cooldown
# marker written AFTER each remediation gates re-firing. The cooldown is short
# (90 s) for fast auto-recovery; the probe timeout is deliberately long
# (240 s > a cold load), so a probe fired mid-reload BLOCKS through the load and
# succeeds rather than false-failing and re-remediating.

set -euo pipefail

api_url="${MLX_API_URL:?MLX_API_URL unset}"
label="${MLX_LAUNCHD_LABEL:?MLX_LAUNCHD_LABEL unset}"
probe_model="${MLX_WATCHDOG_PROBE_MODEL:?MLX_WATCHDOG_PROBE_MODEL unset}"
# Plist the teardown stage re-bootstraps. home-manager writes the agent to
# ~/Library/LaunchAgents/<label>.plist; the LaunchAgent sets this explicitly so
# the layout is not guessed, but keep a HOME-relative fallback for a manual run.
plist="${MLX_WATCHDOG_PLIST:-${HOME}/Library/LaunchAgents/${label}.plist}"
marker="${MLX_WATCHDOG_MARKER:-${HOME}/Library/Caches/vllm-mlx/watchdog-last-kick}"
# Consecutive-failure counter that drives the ladder; cleared on any healthy pass.
fail_marker="${MLX_WATCHDOG_FAIL_MARKER:-${HOME}/Library/Caches/vllm-mlx/watchdog-failures}"
# Untracked file holding an ntfy-style POST url; it names internal topology, so
# it is seeded out-of-band and never committed. Missing file = no page. Shared
# with the cluster watcher on purpose so one seeded url serves both.
alert_url_file="${MLX_WATCHDOG_ALERT_URL_FILE:-${HOME}/.config/mlx-cluster/alert-url}"
# Short cooldown for fast auto-recovery (target 1-2 min). Safe despite covering
# a cold load only because probe_timeout below out-waits the load.
cooldown="${MLX_WATCHDOG_COOLDOWN:-90}"
# A cold load legitimately holds a completion open for minutes; a short timeout
# turns every normal model swap into a false positive.
probe_timeout="${MLX_WATCHDOG_PROBE_TIMEOUT:-240}"
# Reap orphan worker trees above this uid process count. Default sits well above
# steady state (~700) and below kern.maxprocperuid (~10.7k) so it fires only in
# the runaway that precedes fork exhaustion, never in normal operation.
maxproc_threshold="${MLX_WATCHDOG_MAXPROC_THRESHOLD:-8000}"

uid="$(id -u)"
# pgrep/pkill/launchctl/ps/hostname are called by absolute path: on Darwin
# nixpkgs' procps is Apple's (only ps/sysctl/top/watch), and launchctl is a
# system binary — none are on writeShellApplication's sanitized PATH.
worker_pattern='vllm-mlx serve'

mkdir -p "$(dirname "$marker")" "$(dirname "$fail_marker")"

ts() { date -u +%FT%TZ; }

# Read a non-negative integer from a marker file; anything else (missing,
# empty, corrupt partial write) coerces to 0 so `set -e` arithmetic below does
# not crash on "value too great for base". `$(<file)` is a builtin — no fork.
read_int() {
  local v=0
  [[ -r "$1" ]] && v="$(<"$1")"
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

# SIGTERM -> wait -> SIGKILL the worker trees, mirroring llama-swap-launch.sh.
# A wedged engine (broadcast_shapes batch hang) ignores SIGTERM, so the SIGKILL
# escalation is what keeps it from surviving into the next proxy's port.
reap_workers() {
  /usr/bin/pgrep -f "$worker_pattern" >/dev/null 2>&1 || return 0
  echo "$(ts) mlx-watchdog: reaping workers matching '${worker_pattern}'" >&2
  /usr/bin/pkill -f "$worker_pattern" || true
  for _ in $(seq 1 10); do
    /usr/bin/pgrep -f "$worker_pattern" >/dev/null 2>&1 || return 0
    sleep 1
  done
  /usr/bin/pkill -9 -f "$worker_pattern" || true
  sleep 2
}

# Page once via ntfy, only if the untracked url file exists.
alert() {
  [[ -f "$alert_url_file" ]] || return 0
  curl -fsS -m 10 -H "Priority: urgent" \
    -H "Title: mlx-watchdog $(/bin/hostname -s)" \
    -d "$1" "$(<"$alert_url_file")" >/dev/null 2>&1 || true
}

# Healthy iff the response carries at least one generated token. HTTP status and
# finish_reason are both untrustworthy here (mode 2 above), so completion_tokens
# is the only assertion worth making.
probe() {
  local request body
  # Build the body with jq so a model id carrying quotes/backslashes cannot
  # produce invalid JSON — that would fail the probe for a reason unrelated to
  # serving health and remediate a perfectly good proxy.
  request="$(jq -nc --arg model "$probe_model" \
    '{model: $model, messages: [{role: "user", content: "ping"}], max_tokens: 4}')" || return 1
  body="$(curl -s --max-time "$probe_timeout" \
    -H 'Content-Type: application/json' \
    -d "$request" \
    "${api_url}/chat/completions" 2>/dev/null)" || return 1
  jq -e '(.usage.completion_tokens // 0) >= 1' >/dev/null 2>&1 <<<"$body"
}

# Fork-exhaustion awareness, every tick, BEFORE the cooldown gate so it is never
# skipped. One ps + one grep. grep -c prints 0 and exits 1 on no match, which
# `|| true` absorbs under set -e.
procs="$(/bin/ps -axo uid | grep -c "^[[:space:]]*${uid}\$" || true)"
[[ "$procs" =~ ^[0-9]+$ ]] || procs=0
echo "$(ts) mlx-watchdog: uid=${uid} procs=${procs}"
if (( procs > maxproc_threshold )); then
  # ponytail: reaps ALL matching worker trees, not only orphans — worker
  # ancestry cannot distinguish an orphan from a live detached worker (both
  # report PPID 1; see llama-swap-launch.sh). At this threshold the box is
  # already sliding toward fork exhaustion where it cannot even restart itself,
  # so reclaiming slots outweighs a brief serving blip; the probe below then
  # reloads cleanly. Raise the threshold if steady state ever approaches it.
  echo "$(ts) mlx-watchdog: WARN procs=${procs} > ${maxproc_threshold} -> reaping worker trees to reclaim process slots" >&2
  reap_workers
  alert "$(/bin/hostname -s): uid procs=${procs} exceeded ${maxproc_threshold}; reaped vllm-mlx worker trees to avoid fork exhaustion."
fi

# Cadence gate: if we remediated within the cooldown, the proxy may still be
# reloading — do nothing rather than re-remediate it.
now="$(date +%s)"
last="$(read_int "$marker")"
if (( now - last < cooldown )); then
  exit 0
fi

# One transient miss (a hiccup under load, or a swap-in) must not trigger a
# remediation, so require two consecutive failures. A pass resets the ladder.
if probe; then
  rm -f "$fail_marker"
  exit 0
fi
sleep 5
if probe; then
  rm -f "$fail_marker"
  exit 0
fi

# Confirmed not serving. Advance the ladder and start the cooldown NOW, before
# the slow remediation, so the next tick does not re-fire mid-recovery. Writing
# the fail counter before the work means a crashed remediation still escalates.
failures=$(( $(read_int "$fail_marker") + 1 ))
printf '%s\n' "$failures" > "$fail_marker"
printf '%s\n' "$now" > "$marker"

if (( failures == 1 )); then
  # Rung 1: reap orphan workers, then kickstart. The launcher reaps again on the
  # way up, so a wedged/orphaned worker cannot survive into the new proxy.
  echo "$(ts) mlx-watchdog: ${probe_model} produced no tokens x2 (failure 1) -> reap + kickstart ${label}" >&2
  reap_workers
  /bin/launchctl kickstart -k "gui/${uid}/${label}" || true
  exit 0
fi

# Rung 2+: a kickstart already failed to recover, which means the unit is
# throttled or slot-starved — kickstart cannot clear either. Tear it all the way
# down and bootstrap the plist fresh. Page once on entering this stage.
echo "$(ts) mlx-watchdog: ${probe_model} still no tokens (failure ${failures}) -> bootout + bootstrap ${label}" >&2
alert "$(/bin/hostname -s): serving down — ${label} failed kickstart recovery (failure ${failures}); tearing down and bootstrapping. probe model=${probe_model}."

/bin/launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
reap_workers
/usr/bin/pkill -9 -f 'llama-swap' || true

bootstrapped=0
for _ in $(seq 1 5); do
  if /bin/launchctl bootstrap "gui/${uid}" "$plist" 2>/dev/null; then
    bootstrapped=1
    break
  fi
  sleep 5
done
if (( bootstrapped == 0 )); then
  echo "$(ts) mlx-watchdog: bootstrap of ${label} failed after 5 attempts" >&2
  alert "$(/bin/hostname -s): bootstrap of ${label} FAILED after 5 attempts — manual intervention needed."
fi

# bootstrap loads but may not start; kickstart starts it now regardless.
/bin/launchctl kickstart "gui/${uid}/${label}" || true
