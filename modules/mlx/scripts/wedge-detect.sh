# shellcheck shell=bash
# shellcheck disable=SC2154 # every var this file reads (brain_model, api_url,
# busy_escalation, wedge_marker, busy_marker, progress_marker,
# wedge_incident_marker, wedge_incident_window, wedge_incident_max,
# wedge_latency_ms, wedge_consecutive, now) is assigned by mlx-watchdog.sh,
# which mlx-watchdog-pkg.nix concatenates AFTER this file — shellcheck sees
# only this file in isolation and cannot follow the build-time join.
# Wedge detection — function definitions ONLY (no top-level statements), same
# split as llama-swap-reap.sh ahead of llama-swap-launch.sh, concatenated
# ahead of mlx-watchdog.sh by mlx-watchdog-pkg.nix so tests/test-wedge-classify.sh
# can source it directly.
#
# THE DEFECT THIS DETECTS: llama-swap's per-model admission counter
# (internal/router/scheduler/fifo.go, FIFO.reserved) is incremented on every
# admitted request and released exactly once — on a post-admission error, on
# cancellation while queued, or on completion (OnServeDone, via a deferred
# send in internal/router/base.go's trackedServe). Measured on the serving
# host (~/Library/Logs/mlx-model-server/server.log, 63h/17792 requests):
# 65.6% of ALL requests got HTTP 429 while the
# watchdog's own busy/idle probes showed the worker busy only 47% of the
# time, and every one of 11,673 429s answered under 100ms with none slower —
# an in-memory counter answering without touching the model. Static reading
# of the pinned llama-swap v249 admit()/release()/trackedServe() found the
# accounting correctly paired and the completion path unconditionally
# deferred, so the exact leaking line was not pinned down here; llama-swap is
# consumed as an upstream nixpkgs-unstable binary in this repo (see
# default.nix), not vendored source, so there is no local patch to apply —
# this is recovery for the observed symptom, upstream owns the counter fix.
#
# CLUSTER-MODE CONFLICT: recovery here restarts dev.mlx-model-server
# (llama-swap). Entering MLX cluster mode deliberately bootouts that exact
# service (and its warmup unit) to free the memory the shard needs, so
# during a cluster window the service is INTENTIONALLY absent, not failed.
# This detector already no-ops cleanly there — do not "fix" this: a
# connection refused (or any non-429 response) makes wedge_classify return
# clear on the first probe, before any engine-progress read is attempted,
# so a cluster window never accumulates a wedge streak or logs a spurious
# failure. Confirmed by reading wedge_classify/wedge_probe: only an actual
# 429 response can advance the streak. What is NOT proven safe here: the
# separate, pre-existing coarse dead/down branch below in mlx-watchdog.sh,
# which treats the same connection-refused as brain state "down" and calls
# escalate_ladder — and cluster-join does not bootout this watchdog agent
# itself, so it keeps ticking and could bootstrap dev.mlx-model-server back
# during an active cluster window, fighting the cluster for the memory it
# just freed. That is a distinct, pre-existing gap outside this detector's
# scope; flagged, not fixed, here.
#
# THE DISCRIMINATOR (both required — matches the measured evidence exactly,
# see wedge_classify):
#   1. FAST 429 — answered in under wedge_latency_ms. admit() rejects
#      synchronously against an in-memory map with no queueing, so a fast
#      429 alone is NOT proof (a genuinely full model also rejects fast) —
#      but a SLOW 429 (real queueing) rules the wedge out, because none of
#      the measured leaked-slot 429s were slow. A correctly-full admission
#      check rejects just as fast as a leaked counter — both answer
#      synchronously against an in-memory structure with no queueing — so a
#      fast 429 alone carries almost no discriminating power even under
#      genuine heavy load. Condition 2 below is what actually separates a
#      wedge from healthy saturation, and it must stay an independent
#      measurement, never inferred from latency.
#   2. FLAT ENGINE PROGRESS — the physical backend's own scheduler-step
#      counter (vllm_mlx_engine_steps_executed, read via
#      brain_progress_snapshot() in mlx-watchdog.sh) does not advance
#      between two probes a few seconds apart. A genuinely full model is
#      mid-generation and its step counter moves; a leaked reservation has
#      no real work behind it and the counter sits still. This is also what
#      makes the detector safe against restarting a genuine long generation
#      in flight — advancing steps always clears the streak. vllm-mlx only:
#      mlx-lm exposes no per-request metrics (same gate as
#      MLX_WATCHDOG_BUSY_ESCALATION), so on that backend this whole check is
#      a deliberate no-op rather than a guess.
#
# Persistence: a single suspect tick never acts (requirement: never react to
# one observation) — check_wedge tracks its own streak counter, separate
# from the coarse healthy/dead/busy classification's fail_marker, because an
# interspersed healthy request (measured ~34% of real traffic still gets
# served through the wedge) would otherwise wipe the signal every time the
# coarse per-tick state machine below happens to land on "healthy". Recovery
# itself reuses escalate_ladder — the same bounded, cooldown-gated,
# rung1-kickstart/rung2-bootout+bootstrap ladder every other failure mode
# uses — so a confirmed wedge cannot restart-loop any harder than an
# ordinary dead/down brain already can, and it earns the same alert on rung 2.

# wedge_classify http1 ms1 http2 ms2 steps1 steps2 threshold_ms -> prints
# suspect | clear | inconclusive. Pure: no I/O, no globals, no network — the
# two-condition discriminator above, table-driven so it is testable without
# mocking curl or the metrics scrape.
wedge_classify() {
  local http1="$1" ms1="$2" http2="$3" ms2="$4" steps1="$5" steps2="$6" threshold="$7"
  if [[ "$http1" != "429" || "$ms1" -ge "$threshold" || "$http2" != "429" || "$ms2" -ge "$threshold" ]]; then
    printf 'clear'
    return
  fi
  if [[ -z "$steps1" || -z "$steps2" ]]; then
    printf 'inconclusive'
    return
  fi
  if [[ "$steps1" != "$steps2" ]]; then
    printf 'clear'
    return
  fi
  printf 'suspect'
}

# One timed probe against the brain model. Prints "http_code<TAB>latency_ms".
# A dedicated curl call (not probe_once) because it needs %{time_total},
# which the coarse healthy/dead/busy probe never reads.
wedge_probe() {
  local request body_file result http time_total
  request="$(jq -nc --arg model "$brain_model" \
    '{model: $model, messages: [{role: "user", content: "ping"}], max_tokens: 4}')" || {
    printf 'error\t0'
    return
  }
  body_file="$(mktemp)"
  result="$(curl -s -o "$body_file" -w '%{http_code} %{time_total}' --max-time 5 \
    -H 'Content-Type: application/json' -d "$request" \
    "${api_url}/chat/completions" 2>/dev/null)" || result=""
  rm -f "$body_file"
  read -r http time_total <<<"$result"
  [[ -n "$http" ]] || http="error"
  printf '%s\t%.0f' "$http" "$(awk -v t="${time_total:-0}" 'BEGIN { print t * 1000 }')"
}

# Orchestrates one tick's wedge check: two probes ~2s apart, cross-checked
# against engine-step movement via wedge_classify, persisted in $wedge_marker
# across wedge_consecutive ticks before acting. Prints its reasoning every
# branch, including the decision not to act (a silent guard is the exact
# defect class this exists to avoid — see mlx-watchdog.sh's own header for
# the prior incident). Returns 0 if it escalated (already called
# escalate_ladder, so the caller should skip the rest of this tick's now-stale
# probing); 1 otherwise.
check_wedge() {
  if [[ "$busy_escalation" != "restart" ]]; then
    echo "$(ts) mlx-watchdog: wedge-check: backend exposes no engine-progress metric -> skipped"
    return 1
  fi

  local h1 m1 h2 m2 snap1 snap2 steps1="" steps2="" verdict streak
  read -r h1 m1 <<<"$(wedge_probe)"
  snap1="$(brain_progress_snapshot || true)"
  sleep 2
  read -r h2 m2 <<<"$(wedge_probe)"
  snap2="$(brain_progress_snapshot || true)"
  [[ -n "$snap1" ]] && steps1="$(cut -f3 <<<"$snap1")"
  [[ -n "$snap2" ]] && steps2="$(cut -f3 <<<"$snap2")"

  verdict="$(wedge_classify "$h1" "$m1" "$h2" "$m2" "$steps1" "$steps2" "$wedge_latency_ms")"
  case "$verdict" in
    clear)
      echo "$(ts) mlx-watchdog: wedge-check clear (probe1=${h1}/${m1}ms probe2=${h2}/${m2}ms steps=${steps1:-?}->${steps2:-?})"
      rm -f "$wedge_marker"
      return 1
      ;;
    inconclusive)
      echo "$(ts) mlx-watchdog: wedge-check inconclusive — fast 429 twice but no engine metrics -> no action" >&2
      return 1
      ;;
  esac

  streak=$(( $(read_int "$wedge_marker") + 1 ))
  printf '%s\n' "$streak" > "$wedge_marker"
  echo "$(ts) mlx-watchdog: WEDGE SUSPECT streak ${streak}/${wedge_consecutive} — two fast 429s (${m1}ms, ${m2}ms) with flat engine steps (${steps1})" >&2

  if (( streak < wedge_consecutive )); then
    echo "$(ts) mlx-watchdog: wedge streak ${streak}/${wedge_consecutive} -> waiting, no restart yet"
    return 1
  fi

  # Do NOT clear fail_marker here — mirror the dead|down branch below exactly,
  # so a wedge-triggered restart and a coarse dead/down restart share the same
  # rung-escalation memory in escalate_ladder (two failures close together,
  # from either cause, still reach rung 2's bootout+bootstrap+alert).
  rm -f "$wedge_marker" "$busy_marker" "$progress_marker"

  # A SEPARATE, healthy-immune counter bounds repeated wedge recovery itself.
  # fail_marker is not enough: the leak re-accumulates slowly enough that
  # plenty of healthy completions land between incidents (measured ~34% of
  # traffic still succeeds even while wedged), and the coarse `healthy` case
  # below unconditionally clears fail_marker on any single healthy probe — so
  # a wedge that re-leaks every ~15 min would otherwise reach rung 1 forever,
  # cold-reloading both residents every time with no page ever sent. This
  # counter only resets on its own window expiry, never on a healthy probe.
  local incident_since=0 incident_count=0
  if [[ -r "$wedge_incident_marker" ]]; then
    read -r incident_since incident_count < "$wedge_incident_marker" || true
  fi
  [[ "$incident_since" =~ ^[0-9]+$ ]] || incident_since=0
  [[ "$incident_count" =~ ^[0-9]+$ ]] || incident_count=0
  if (( incident_since == 0 || now - incident_since > wedge_incident_window )); then
    incident_since="$now"
    incident_count=0
  fi
  incident_count=$(( incident_count + 1 ))
  printf '%s\t%s\n' "$incident_since" "$incident_count" > "$wedge_incident_marker"

  if (( incident_count > wedge_incident_max )); then
    echo "$(ts) mlx-watchdog: wedge fired ${incident_count} times within ${wedge_incident_window}s (max ${wedge_incident_max}) -> HOLDING, NOT restarting again -- alerting instead" >&2
    alert "$(/bin/hostname -s): llama-swap slot-accounting wedge recurred ${incident_count} times in ${wedge_incident_window}s on brain '${brain_model}' — held, NOT restarting again (bounded). Restarting is not fixing this; investigate the counter leak itself."
    return 1
  fi

  echo "$(ts) mlx-watchdog: wedge incident ${incident_count}/${wedge_incident_max} within ${wedge_incident_window}s -> proceeding with recovery"
  escalate_ladder "slot-accounting wedge: ${wedge_consecutive} consecutive fast-429/flat-engine observations (brain ${brain_model}, incident ${incident_count}/${wedge_incident_max} in ${wedge_incident_window}s)"
  return 0
}
