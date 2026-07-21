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
# Probe outcome discrimination (a non-answer is NOT always a failure):
# curl's transport exit code and the HTTP status are read separately, then each
# probe is classed as one of four states. Only two of them are real failures:
#   - healthy : HTTP 200 with completion_tokens >= 1. Resets counters.
#   - dead    : HTTP 200 with zero tokens/empty content (mode 2), or any other
#               HTTP status carrying no completion. The engine/parser answered
#               but did not serve -> a real failure, escalates the ladder.
#   - busy    : HTTP 429, a curl timeout (queued behind a long request), or a
#               transient transport blip (empty reply / recv error), OR a
#               connection refused while the launchd unit still reports running
#               (a load/restart in flight). NOT a failure: a busy or loading
#               proxy must not be torn down mid-work. Logged, never counted,
#               until it persists past the grace window below.
#   - down    : connection refused AND the launchd unit is NOT running. The
#               proxy is gone and launchd has not brought it back -> escalate.
#
# Blast-radius scoping (the fix for brain-flapping): a multi-resident host warms
# a coder model plus the fleet brain. A coder swap/queue transient used to trip
# the ladder and restart the ENTIRE stack, including a perfectly healthy brain.
# Now every preloaded model is probed, but only the BRAIN model (MLX_WATCHDOG_-
# BRAIN_MODEL) may trigger the full-stack ladder. A non-brain model that is dead
# only fires an ntfy alert for a human to look at that one worker; it never
# restarts the stack. The brain is always in the probe set, so "every model
# failing" surfaces as a dead/down brain and escalates on its own.
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
#   - A healthy brain resets the counter and cooldown.
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
# succeeds rather than false-failing and re-remediating. The busy state adds a
# second, longer gate: a brain that stays busy/loading past a grace window
# (default 15 min) with no successful completion is treated as stuck and
# escalated, so a genuinely wedged-but-listening proxy is not waited on forever.

set -euo pipefail

api_url="${MLX_API_URL:?MLX_API_URL unset}"
label="${MLX_LAUNCHD_LABEL:?MLX_LAUNCHD_LABEL unset}"
# Plist the teardown stage re-bootstraps. home-manager writes the agent to
# ~/Library/LaunchAgents/<label>.plist; the LaunchAgent sets this explicitly so
# the layout is not guessed, but keep a HOME-relative fallback for a manual run.
plist="${MLX_WATCHDOG_PLIST:-${HOME}/Library/LaunchAgents/${label}.plist}"
marker="${MLX_WATCHDOG_MARKER:-${HOME}/Library/Caches/vllm-mlx/watchdog-last-kick}"
# Consecutive-failure counter that drives the ladder; cleared on any healthy pass.
fail_marker="${MLX_WATCHDOG_FAIL_MARKER:-${HOME}/Library/Caches/vllm-mlx/watchdog-failures}"
# Wall-clock timestamp of the first tick the brain went busy; cleared when it
# serves again. Drives the busy grace window so a stuck-busy proxy still escalates.
busy_marker="${MLX_WATCHDOG_BUSY_MARKER:-${HOME}/Library/Caches/vllm-mlx/watchdog-brain-busy-since}"
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
# A brain that stays busy/loading this long with no successful completion is
# treated as stuck and escalated (default 15 min = the cron cadence, so a real
# outage is not sat on longer than one cron gap). Distinct from a real failure,
# which escalates immediately.
busy_grace="${MLX_WATCHDOG_BUSY_GRACE:-900}"
# Reap orphan worker trees above this uid process count. Default sits well above
# steady state (~700) and below kern.maxprocperuid (~10.7k) so it fires only in
# the runaway that precedes fork exhaustion, never in normal operation.
maxproc_threshold="${MLX_WATCHDOG_MAXPROC_THRESHOLD:-8000}"

# Models to probe each tick. Preferred: the full resident set as a JSON array
# (MLX_WATCHDOG_PROBE_MODELS_JSON, mirrors the warmup agent's preload list).
# Fallback: a single model id for a manual/legacy run. The brain defaults to the
# first probed model, but a multi-resident host names it explicitly so a coder
# transient can never restart the brain.
probe_models=()
if [[ -n "${MLX_WATCHDOG_PROBE_MODELS_JSON:-}" ]]; then
  while IFS= read -r m; do
    [[ -n "$m" ]] && probe_models+=("$m")
  done < <(jq -r '.[]' <<<"$MLX_WATCHDOG_PROBE_MODELS_JSON" 2>/dev/null)
fi
if (( ${#probe_models[@]} == 0 )); then
  probe_models=( "${MLX_WATCHDOG_PROBE_MODEL:?set MLX_WATCHDOG_PROBE_MODELS_JSON or MLX_WATCHDOG_PROBE_MODEL}" )
fi
brain_model="${MLX_WATCHDOG_BRAIN_MODEL:-${probe_models[0]}}"

uid="$(id -u)"
# pgrep/pkill/launchctl/ps/hostname are called by absolute path: on Darwin
# nixpkgs' procps is Apple's (only ps/sysctl/top/watch), and launchctl is a
# system binary — none are on writeShellApplication's sanitized PATH.
worker_pattern='vllm-mlx serve'

mkdir -p "$(dirname "$marker")" "$(dirname "$fail_marker")" "$(dirname "$busy_marker")"

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

# True iff launchd reports the serving agent as running (mirrors the readiness
# check in cluster-link-watcher.sh). Distinguishes "refused because loading"
# from "refused because the proxy is gone".
unit_running() {
  /bin/launchctl print "gui/${uid}/${label}" 2>/dev/null | grep -q "state = running"
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

# One probe of one model, classified into: healthy | dead | busy | down.
# curl's transport exit code and the HTTP status are read separately (-w
# %{http_code} to stdout, body to a temp file) — conflating them is what made a
# 429 or a timeout look identical to a wedged engine.
probe_once() {
  local model="$1" request body_file http curl_rc body
  # Build the body with jq so a model id carrying quotes/backslashes cannot
  # produce invalid JSON — that would fail the probe for a reason unrelated to
  # serving health and remediate a perfectly good proxy.
  request="$(jq -nc --arg model "$model" \
    '{model: $model, messages: [{role: "user", content: "ping"}], max_tokens: 4}')" || {
    printf 'dead'
    return
  }
  body_file="$(mktemp)"
  set +e
  http="$(curl -s -o "$body_file" -w '%{http_code}' --max-time "$probe_timeout" \
    -H 'Content-Type: application/json' \
    -d "$request" \
    "${api_url}/chat/completions" 2>/dev/null)"
  curl_rc=$?
  set -e
  body="$(cat "$body_file" 2>/dev/null || true)"
  rm -f "$body_file"

  # Transport-level outcomes first (no usable HTTP status).
  if (( curl_rc == 7 )); then
    # Connection refused / no listener. A loading proxy refuses briefly; a gone
    # proxy that launchd has not restarted is a real outage.
    if unit_running; then printf 'busy'; else printf 'down'; fi
    return
  fi
  if (( curl_rc != 0 )); then
    # Timeout (28, queued behind a long request) or a transient blip (52 empty
    # reply, 56 recv error). Busy, not wedged.
    printf 'busy'
    return
  fi

  # HTTP layer answered.
  if [[ "$http" == "200" ]]; then
    if jq -e '(.usage.completion_tokens // 0) >= 1' >/dev/null 2>&1 <<<"$body"; then
      printf 'healthy'
    else
      printf 'dead'
    fi
    return
  fi
  if [[ "$http" == "429" ]]; then
    printf 'busy'
    return
  fi
  # Any other status (4xx/5xx) carried no completion: a real not-serving answer.
  printf 'dead'
}

# Confirmed state of one model: require two consecutive non-healthy probes 5 s
# apart before believing a failure, so one hiccup under load never escalates. A
# recovery on the second probe reads as healthy.
probe_model_state() {
  local model="$1" state
  state="$(probe_once "$model")"
  [[ "$state" == "healthy" ]] && { printf 'healthy'; return; }
  sleep 5
  probe_once "$model"
}

# The escalation ladder (#1319), now parameterized by the reason that triggered
# it so a brain-failure and a stuck-busy escalation read distinctly in the logs
# and the page. Advances the counter and starts the cooldown NOW, before the
# slow remediation, so the next tick does not re-fire mid-recovery; writing the
# counter before the work means a crashed remediation still escalates.
escalate_ladder() {
  local reason="$1" failures bootstrapped
  failures=$(( $(read_int "$fail_marker") + 1 ))
  printf '%s\n' "$failures" > "$fail_marker"
  printf '%s\n' "$now" > "$marker"

  if (( failures == 1 )); then
    # Rung 1: reap orphan workers, then kickstart. The launcher reaps again on
    # the way up, so a wedged/orphaned worker cannot survive into the new proxy.
    echo "$(ts) mlx-watchdog: ${reason} (failure 1) -> reap + kickstart ${label}" >&2
    reap_workers
    /bin/launchctl kickstart -k "gui/${uid}/${label}" || true
    return
  fi

  # Rung 2+: a kickstart already failed to recover, which means the unit is
  # throttled or slot-starved — kickstart cannot clear either. Tear it all the
  # way down and bootstrap the plist fresh. Page once on entering this stage.
  echo "$(ts) mlx-watchdog: ${reason} (failure ${failures}) -> bootout + bootstrap ${label}" >&2
  alert "$(/bin/hostname -s): serving down — ${reason}; failed kickstart recovery (failure ${failures}); tearing down and bootstrapping."

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

# Probe every resident model, recording the brain's state and any non-brain
# failures. The brain is normally in the probe set; if a host names a brain
# outside its preload list, probe it explicitly at the end.
brain_state=""
dead_nonbrain=()
for m in "${probe_models[@]}"; do
  state="$(probe_model_state "$m")"
  echo "$(ts) mlx-watchdog: probe model=${m} state=${state}"
  if [[ "$m" == "$brain_model" ]]; then
    brain_state="$state"
  elif [[ "$state" == "dead" || "$state" == "down" ]]; then
    dead_nonbrain+=("$m")
  fi
done
if [[ -z "$brain_state" ]]; then
  brain_state="$(probe_model_state "$brain_model")"
  echo "$(ts) mlx-watchdog: probe brain=${brain_model} state=${brain_state} (not in preload set)"
fi

# A non-brain model that is not serving is a real problem for that worker, but
# NOT a reason to restart the whole stack (and take a healthy brain down with
# it). Page a human and move on. This runs regardless of the brain's state; the
# brain decision below owns any stack action.
if (( ${#dead_nonbrain[@]} > 0 )); then
  for m in "${dead_nonbrain[@]}"; do
    echo "$(ts) mlx-watchdog: non-brain model ${m} not serving -> alert only, NO stack restart" >&2
    alert "$(/bin/hostname -s): non-brain model '${m}' not serving; NOT restarting the stack (brain=${brain_model} state=${brain_state}). Investigate that worker."
  done
fi

# The brain decision owns the blast radius.
case "$brain_state" in
  healthy)
    # Serving. Clear the ladder and the busy window.
    rm -f "$fail_marker" "$busy_marker"
    exit 0
    ;;
  dead | down)
    # A real not-serving answer from the brain -> remediate the stack now.
    rm -f "$busy_marker"
    escalate_ladder "brain ${brain_model} not serving (state=${brain_state})"
    exit 0
    ;;
  busy)
    # Busy or loading: do NOT tear down mid-work. Track how long the brain has
    # been continuously busy; escalate only once it passes the grace window with
    # no successful completion, so a genuinely wedged-but-listening proxy is not
    # waited on forever.
    busy_since="$(read_int "$busy_marker")"
    if (( busy_since == 0 )); then
      busy_since="$now"
      printf '%s\n' "$busy_since" > "$busy_marker"
    fi
    busy_for=$(( now - busy_since ))
    if (( busy_for >= busy_grace )); then
      rm -f "$busy_marker"
      escalate_ladder "brain ${brain_model} stuck busy/loading for ${busy_for}s (no completion through ${busy_grace}s grace)"
    else
      echo "$(ts) mlx-watchdog: brain ${brain_model} busy/loading (${busy_for}s < ${busy_grace}s grace) -> waiting, no restart"
    fi
    exit 0
    ;;
  *)
    # Unreachable: probe_model_state only emits the four known states.
    echo "$(ts) mlx-watchdog: brain ${brain_model} unknown state '${brain_state}' -> no action" >&2
    exit 0
    ;;
esac
