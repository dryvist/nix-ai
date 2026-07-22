#!/usr/bin/env bash
# mlx-watchdog - self-heal a serving host that is up but not serving.
#
# KeepAlive=true only restarts the proxy on process EXIT, so a live-but-useless
# proxy is invisible to launchd, and /v1/models stays 200 through every such
# mode (llama-swap answers it from static config, no model). The only signal
# that separates "serving" from "up" is a real completion that yields a token,
# so that is what this probes against a resident model. Zammad: AI/LLM Serving
# INC-17114.
#
# Probe outcome discrimination — a non-answer is NOT always a failure. curl's
# transport exit code and the HTTP status are read separately, then classed:
#   healthy : HTTP 200, completion_tokens >= 1              -> reset counters
#   dead    : HTTP 200 zero tokens, or other status no body -> real failure
#   busy    : HTTP 429, curl timeout/blip, or refused while -> NOT a failure;
#             the unit still runs (loading/queued)             grace-gated
#   down    : refused AND the unit is not running           -> escalate
# completion_tokens, not status, is the assertion: a wedged scheduler answers
# 200 with zero tokens and litellm remaps that finish_reason to "stop".
#
# Blast-radius scoping (the fix for brain-flapping): every preloaded model is
# probed, but only the BRAIN (MLX_WATCHDOG_BRAIN_MODEL) may trigger the
# full-stack ladder. A dead non-brain model only pages; it never restarts the
# stack — so a coder swap can no longer flap a healthy fleet brain. The brain is
# always in the probe set, so "every model failing" surfaces as a dead/down brain.
#
# A confirmed brain failure escalates a persisted counter (escalate_ladder):
# failure 1 kickstarts, failure 2+ tears down and bootstraps — a single
# kickstart cannot clear a throttled or slot-starved unit. A busy brain is
# grace-gated instead; a cooldown marker stops a slow reload being restart-
# stormed; fork-exhaustion is guarded every tick. Details live at each code site.

set -euo pipefail

api_url="${MLX_API_URL:?MLX_API_URL unset}"
label="${MLX_LAUNCHD_LABEL:?MLX_LAUNCHD_LABEL unset}"
# Plist the rung-2 teardown re-bootstraps after bootout.
plist="${MLX_WATCHDOG_PLIST:-${HOME}/Library/LaunchAgents/${label}.plist}"
# Cooldown marker (last remediation), failure counter (ladder), and the
# timestamp the brain first went busy — all cleared on a healthy brain.
marker="${MLX_WATCHDOG_MARKER:-${HOME}/Library/Caches/mlx-model-server/watchdog-last-kick}"
fail_marker="${MLX_WATCHDOG_FAIL_MARKER:-${HOME}/Library/Caches/mlx-model-server/watchdog-failures}"
busy_marker="${MLX_WATCHDOG_BUSY_MARKER:-${HOME}/Library/Caches/mlx-model-server/watchdog-brain-busy-since}"
# Last authoritative progress sample for the brain's physical worker. A busy
# probe is expected while its single slot is occupied; advancing engine steps
# prove the scheduler is productive and rebase the stuck timer.
progress_marker="${MLX_WATCHDOG_PROGRESS_MARKER:-${HOME}/Library/Caches/mlx-model-server/watchdog-brain-progress}"
llama_swap_config="${MLX_WATCHDOG_CONFIG:-${HOME}/.config/mlx/llama-swap.json}"
# Untracked ntfy POST url (names internal topology, never committed; missing =
# no page). Shared with the cluster watcher so one seeded url serves both.
alert_url_file="${MLX_WATCHDOG_ALERT_URL_FILE:-${HOME}/.config/mlx-cluster/alert-url}"
# Untracked healthchecks-style deadman OK-ping url (the UUID is secret-tier, so
# never committed — seeded out of band exactly like the alert url above).
# Missing file = no ping.
healthcheck_url_file="${MLX_WATCHDOG_HEALTHCHECK_URL_FILE:-${HOME}/.config/mlx-cluster/healthcheck-url}"
# Short cooldown for fast recovery; probe timeout out-waits a cold load.
cooldown="${MLX_WATCHDOG_COOLDOWN:-90}"
probe_timeout="${MLX_WATCHDOG_PROBE_TIMEOUT:-240}"
# Escalate a brain busy this long with no completion (15 min).
busy_grace="${MLX_WATCHDOG_BUSY_GRACE:-900}"
# Reap orphan worker trees above this uid process count (above steady state
# ~700, below kern.maxprocperuid ~10.7k): fires only in a runaway.
maxproc_threshold="${MLX_WATCHDOG_MAXPROC_THRESHOLD:-8000}"

# Models to probe: the full resident set as a JSON array
# (MLX_WATCHDOG_PROBE_MODELS_JSON), or a single model id fallback for a manual
# run. Brain defaults to the first probed model.
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
# pgrep/pkill/launchctl/ps/hostname go by absolute path — not on
# writeShellApplication's sanitized PATH.
worker_pattern="${MLX_MODEL_SERVER_PROCESS_PATTERN:?MLX_MODEL_SERVER_PROCESS_PATTERN unset}"

mkdir -p "$(dirname "$marker")" "$(dirname "$fail_marker")" \
  "$(dirname "$busy_marker")" "$(dirname "$progress_marker")"

ts() { date -u +%FT%TZ; }

# Read a non-negative integer from a marker; missing/empty/corrupt coerces to 0
# so `set -e` arithmetic does not crash.
read_int() {
  local v=0
  [[ -r "$1" ]] && v="$(<"$1")"
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

# True iff launchd reports the serving agent running — distinguishes "refused
# because loading" from "refused, gone" (mirrors cluster-link-watcher.sh).
unit_running() {
  /bin/launchctl print "gui/${uid}/${label}" 2>/dev/null | grep -q "state = running"
}

# SIGTERM -> wait -> SIGKILL the worker trees. A wedged engine ignores SIGTERM,
# so the SIGKILL keeps it out of the next proxy's port (see llama-swap-launch.sh).
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

# Ping the external deadman OK endpoint on a healthy brain, only if the url file
# exists. When these pings stop — this host down/asleep, launchd wedged, or the
# brain not serving — the external check pages on its own. It is the only signal
# that survives this whole host going silent, which no on-host alert can emit.
# Missing file = no-op.
hc_ping() {
  [[ -f "$healthcheck_url_file" ]] || return 0
  curl -fsS -m 8 "$(<"$healthcheck_url_file")" >/dev/null 2>&1 || true
}

# Return "physical-model<TAB>backend-url<TAB>steps<TAB>uptime" for the brain.
# The mutable llama-swap config maps the capability alias to exactly one
# physical model; /running then maps that model to its own metrics endpoint.
# vllm_mlx_engine_steps_executed increments on every scheduler step, including
# during one long request. Engine uptime distinguishes a reset epoch. Missing,
# duplicated, or malformed metrics are fail-closed: the existing busy timer
# continues without being reset.
brain_progress_snapshot() {
  local physical api_root running backend metrics engine_state steps uptime
  [[ -r "$llama_swap_config" ]] || return 1
  physical="$(jq -er --arg brain "$brain_model" '
    [
      .models
      | to_entries[]
      | select(.key == $brain or ((.value.aliases // []) | index($brain)))
      | .key
    ]
    | if length == 1 then .[0] else empty end
  ' "$llama_swap_config" 2>/dev/null)" || return 1

  api_root="${api_url%/v1}"
  running="$(curl -fsS --max-time 5 "${api_root}/running" 2>/dev/null)" || return 1
  backend="$(jq -er --arg model "$physical" '
    [.running[] | select(.model == $model and .state == "ready") | .proxy]
    | if length == 1 then .[0] else empty end
  ' <<<"$running" 2>/dev/null)" || return 1
  metrics="$(curl -fsS --max-time 5 "${backend}/metrics" 2>/dev/null)" || return 1
  engine_state="$(awk '
    $1 == "vllm_mlx_engine_steps_executed" { steps = $2; step_count++ }
    $1 == "vllm_mlx_engine_uptime_seconds" { uptime = $2; uptime_count++ }
    END {
      if (step_count != 1 || uptime_count != 1) exit 1
      printf "%.0f\t%.0f\n", steps, uptime
    }
  ' <<<"$metrics")" || return 1
  IFS=$'\t' read -r steps uptime <<<"$engine_state"
  [[ "$steps" =~ ^[0-9]+$ && "$uptime" =~ ^[0-9]+$ ]] || return 1
  printf '%s\t%s\t%s\t%s\n' "$physical" "$backend" "$steps" "$uptime"
}

# One probe of one model -> healthy | dead | busy | down. Body to a temp file,
# HTTP status via -w, curl exit code captured separately.
probe_once() {
  local model="$1" request body_file http curl_rc body
  # jq builds the body so a model id with quotes cannot yield invalid JSON.
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

  # Transport outcomes first: refused while loading vs refused-and-gone;
  # timeout/blip is just busy.
  if (( curl_rc == 7 )); then
    if unit_running; then printf 'busy'; else printf 'down'; fi
    return
  fi
  if (( curl_rc != 0 )); then
    printf 'busy'
    return
  fi

  if [[ "$http" == "200" ]]; then
    if jq -e '(.usage.completion_tokens // 0) >= 1' >/dev/null 2>&1 <<<"$body"; then
      printf 'healthy'
    else
      printf 'dead'
    fi
    return
  fi
  [[ "$http" == "429" ]] && { printf 'busy'; return; }
  # Any other status carried no completion: a real not-serving answer.
  printf 'dead'
}

# Require two consecutive non-healthy probes 5 s apart before believing a
# failure, so one hiccup never escalates.
probe_model_state() {
  local model="$1" state
  state="$(probe_once "$model")"
  [[ "$state" == "healthy" ]] && { printf 'healthy'; return; }
  sleep 5
  probe_once "$model"
}

# The ladder, parameterized by the triggering reason. Advances the counter and
# starts the cooldown BEFORE the slow remediation, so the next tick does not
# re-fire mid-recovery and a crashed remediation still escalates.
escalate_ladder() {
  local reason="$1" failures bootstrapped
  failures=$(( $(read_int "$fail_marker") + 1 ))
  printf '%s\n' "$failures" > "$fail_marker"
  printf '%s\n' "$now" > "$marker"

  if (( failures == 1 )); then
    echo "$(ts) mlx-watchdog: ${reason} (failure 1) -> reap + kickstart ${label}" >&2
    reap_workers
    /bin/launchctl kickstart -k "gui/${uid}/${label}" || true
    return
  fi

  # Rung 2+: kickstart already failed, so the unit is throttled/slot-starved —
  # only a full teardown + bootstrap clears that. Page on entering this stage.
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

# Fork-exhaustion guard, every tick, BEFORE the cooldown gate so it is never
# skipped. grep -c prints 0 and exits 1 on no match, absorbed by `|| true`.
procs="$(/bin/ps -axo uid | grep -c "^[[:space:]]*${uid}\$" || true)"
[[ "$procs" =~ ^[0-9]+$ ]] || procs=0
echo "$(ts) mlx-watchdog: uid=${uid} procs=${procs}"
if (( procs > maxproc_threshold )); then
  # ponytail: reaps ALL matching trees, not only orphans — a detached worker and
  # an orphan both report PPID 1 (see llama-swap-launch.sh). At this threshold
  # reclaiming slots outweighs a brief serving blip. Raise if steady state nears it.
  echo "$(ts) mlx-watchdog: WARN procs=${procs} > ${maxproc_threshold} -> reaping worker trees to reclaim process slots" >&2
  reap_workers
  alert "$(/bin/hostname -s): uid procs=${procs} exceeded ${maxproc_threshold}; reaped mlx_lm.server worker trees to avoid fork exhaustion."
fi

# Cadence gate: if we remediated within the cooldown, the proxy may still be
# reloading — do nothing rather than re-remediate.
now="$(date +%s)"
last="$(read_int "$marker")"
if (( now - last < cooldown )); then
  exit 0
fi

# Probe every resident model; record the brain's state and any dead non-brain.
# Probe the brain explicitly if a host names one outside its preload list.
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

# A dead non-brain model is a real problem for that worker but NOT a reason to
# restart the whole stack. Page and move on; the brain decision owns any action.
if (( ${#dead_nonbrain[@]} > 0 )); then
  for m in "${dead_nonbrain[@]}"; do
    echo "$(ts) mlx-watchdog: non-brain model ${m} not serving -> alert only, NO stack restart" >&2
    alert "$(/bin/hostname -s): non-brain model '${m}' not serving; NOT restarting the stack (brain=${brain_model} state=${brain_state}). Investigate that worker."
  done
fi

case "$brain_state" in
  healthy)
    hc_ping   # external deadman OK: brain serving this cycle (survives host going silent)
    rm -f "$fail_marker" "$busy_marker" "$progress_marker"
    exit 0
    ;;
  dead | down)
    rm -f "$busy_marker" "$progress_marker"
    escalate_ladder "brain ${brain_model} not serving (state=${brain_state})"
    exit 0
    ;;
  busy)
    # Do NOT tear down productive work. A single-slot brain correctly returns
    # 429 while generating, so reset the stuck timer whenever that exact
    # physical worker's scheduler-step counter advances. A counter/uptime
    # reset or backend identity change starts a new worker epoch and also gets
    # a fresh grace. Frozen or unavailable metrics retain the 900 s ladder.
    busy_since="$(read_int "$busy_marker")"
    if (( busy_since == 0 )); then
      busy_since="$now"
      printf '%s\n' "$busy_since" > "$busy_marker"
    fi
    snapshot="$(brain_progress_snapshot || true)"
    if [[ -n "$snapshot" ]]; then
      IFS=$'\t' read -r progress_model progress_backend steps_now uptime_now <<<"$snapshot"
      steps_previous=0
      uptime_previous=0
      if [[ -r "$progress_marker" ]]; then
        IFS=$'\t' read -r previous_model previous_backend steps_previous uptime_previous < "$progress_marker" || true
      fi
      if [[ "$steps_previous" =~ ^[0-9]+$ && "$uptime_previous" =~ ^[0-9]+$ ]]; then
        progress_reason=""
        if [[ "$progress_model" != "${previous_model:-}" || "$progress_backend" != "${previous_backend:-}" ]]; then
          progress_reason="worker identity changed"
        elif (( steps_now < steps_previous || uptime_now < uptime_previous )); then
          progress_reason="worker epoch reset"
        elif (( steps_now > steps_previous )); then
          progress_reason="engine steps advanced ${steps_previous}->${steps_now}"
        fi
      else
        progress_reason=""
      fi
      if [[ -n "$progress_reason" ]]; then
        busy_since="$now"
        printf '%s\n' "$busy_since" > "$busy_marker"
        echo "$(ts) mlx-watchdog: brain ${brain_model} ${progress_reason} -> reset busy grace"
      fi
      printf '%s\t%s\t%s\t%s\n' "$progress_model" "$progress_backend" "$steps_now" "$uptime_now" > "$progress_marker"
    fi
    busy_for=$(( now - busy_since ))
    if (( busy_for >= busy_grace )); then
      rm -f "$busy_marker" "$progress_marker"
      escalate_ladder "brain ${brain_model} stuck busy/loading for ${busy_for}s (no engine progress through ${busy_grace}s grace)"
    else
      echo "$(ts) mlx-watchdog: brain ${brain_model} busy/loading (${busy_for}s < ${busy_grace}s grace) -> waiting, no restart"
    fi
    exit 0
    ;;
  *)
    echo "$(ts) mlx-watchdog: brain ${brain_model} unknown state '${brain_state}' -> no action" >&2
    exit 0
    ;;
esac
