# shellcheck shell=bash
# Cluster peer-liveness supervisor — one state-machine tick per launchd interval.
#
# The gap this closes: a dead peer and a wedged peer are INDISTINGUISHABLE from
# the coordinator, so any worker-side failure becomes an indefinite silent hang.
# Rank 0 blocks forever inside jaccl::MeshImpl::recv with no error, no timeout
# and no log line, while /v1/models keeps answering 200 throughout. Two
# instances in one night:
#
#   * the worker died at startup — "ValueError: The model does not support
#     pipelining but a pipeline_group was provided". The coordinator hung 180s
#     and emitted zero bytes. The traceback naming the cause was sitting in the
#     WORKER's own log and nothing surfaced it.
#   * the worker stalled in a Metal GPU fence. The coordinator hung 900s with
#     both ranks at ~100% CPU.
#
# It fooled an experienced operator twice in one night while he was actively
# hunting it. Upstream mlx-lm has no peer liveness and no receive timeout, and
# cannot be patched here, so detection has to live in this supervision layer.
#
# What is and is not evidence is argued in ./cluster-peer-observe.sh, which
# defines every predicate used below. Short version: tokens only.
#
# NOT KILLING HEALTHY RANKS is the hard constraint, because mlx_lm.server
# blocks HTTP for the duration of a generation, so a busy rank fails a naive
# timed probe. Four independent brakes, none of which is "shorten the timeout":
#   1. real traffic short-circuits everything — new token lines in the rank log
#      mean the mesh is alive, so no probe is even attempted
#   2. an ESTABLISHED client connection on the endpoint means a request is in
#      flight; the tick backs off without probing
#   3. probes are rate-limited to one per CLUSTER_PEER_PROBE_INTERVAL_SECS, and
#      each gets a generous CLUSTER_PEER_PROBE_TIMEOUT_SECS
#   4. only CLUSTER_PEER_STRIKES CONSECUTIVE failures escalate; any success,
#      anywhere, clears the count
# At the defaults that is ~15 minutes of provably zero tokens, with no client
# request open, before anything is torn down.
#
# ROLES — there is no SSH between the nodes (see cluster-mode.nix), so neither
# host can read the other's process table or logs. Each side reports the thing
# only it can see, and the two pages correlate by hostname:
#   coordinator — owns token progress and the teardown decision
#   worker      — owns "my rank died", and pages WITH the Python traceback that
#                 killed it. That traceback is the actual cause, and it is
#                 invisible to the coordinator by construction.
#
# Escalation follows the shape cluster-link-watcher.sh already established for
# its PD-guard halt: stop the rank, drop the halt marker so the watcher stops
# kickstarting it, restore the standalone wired ceiling, re-warm standalone
# serving, page once. Sitting wedged is never an outcome.
#
# Consumed environment beyond what ./cluster-peer-observe.sh documents. Every
# threshold is an option in ../peer-liveness.nix — no magic numbers:
#   CLUSTER_ROLE                      coordinator | worker
#   CLUSTER_PEER_PROBE_INTERVAL_SECS  minimum seconds between active probes
#   CLUSTER_PEER_STRIKES              consecutive failed probes before teardown
#   CLUSTER_PEER_DEAD_TICKS           worker: ticks with a down rank before paging
# Inherited from the watcher's contract and consumed by the shared helpers in
# ./cluster-link-helpers.sh (alert, set_wired_limit, restore_normal_serving):
#   CLUSTER_ALERT_URL_FILE CLUSTER_WARMUP_LABEL CLUSTER_SERVER_LABEL
#   CLUSTER_SERVER_PLIST CLUSTER_RESTORE_CMD CLUSTER_NORMAL_PROXY
#   CLUSTER_WIRED_LIMIT_MB CLUSTER_STANDALONE_WIRED_LIMIT_MB

role="${CLUSTER_ROLE:?CLUSTER_ROLE unset}"
rank_label="${CLUSTER_RANK_LABEL:?CLUSTER_RANK_LABEL unset}"
state_file="${CLUSTER_STATE_FILE:?CLUSTER_STATE_FILE unset}"
: "${CLUSTER_STATIC_PEER_IP:?CLUSTER_STATIC_PEER_IP unset}"

probe_interval="${CLUSTER_PEER_PROBE_INTERVAL_SECS:-300}"
max_strikes="${CLUSTER_PEER_STRIKES:-3}"
dead_ticks_max="${CLUSTER_PEER_DEAD_TICKS:-3}"

uid="$(id -u)"
host="$(hostname -s 2> /dev/null || echo unknown)"
state_dir="$(dirname "$state_file")"
mkdir -p "$state_dir"

# Markers owned by the watcher — read here, never written, except halt_file,
# which is the deliberate shared latch (see escalate).
halt_file="$state_dir/rank-halted"
ready_file="$state_dir/rank-ready"
# Markers owned by this supervisor.
strikes_file="$state_dir/peer-strikes"
probed_file="$state_dir/peer-last-probe"
dead_file="$state_dir/peer-rank-down-ticks"
reported_file="$state_dir/peer-reported"

clear_progress_state() { rm -f "$strikes_file" "$probed_file"; }
reset_state() { rm -f "$strikes_file" "$probed_file" "$dead_file" "$reported_file"; }

# Confirmed no token progress: name the cause, page with the evidence, then get
# OUT of the wedged state rather than sitting in it.
#
# Order matters. The halt marker is dropped only once the rank is actually
# down, because the watcher deletes that marker on every tick that sees the
# rank running — touching it first would race the next watcher tick into
# kickstarting the rank this function just killed.
escalate() {
  local cause="$1" evidence="$2" fault
  fault="$(rank_fault_line)"
  echo "cluster-peer: NO TOKEN PROGRESS — $cause" >&2
  CLUSTER_ALERT_PREFIX=":rotating_light: *mlx-cluster no token progress*" \
    alert "$host ($role): $cause
$evidence${fault:+
last exception seen locally: $fault}
Tearing down to standalone serving. Clear: replug the link, or rm $halt_file.
--- rank log tail ---
$(log_tail)"
  launchctl kill SIGTERM "gui/$uid/$rank_label" 2> /dev/null || true
  if rank_running; then
    echo "cluster-peer: WARN rank still running after SIGTERM; not halting kickstarts" >&2
  else
    touch "$halt_file"
  fi
  if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
    set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
  fi
  restore_normal_serving || true
  clear_progress_state
}

# Coordinator: the only rank that binds the endpoint, so the only one that can
# observe a token at all.
coordinator_tick() {
  local progressed now last strikes cause evidence
  progressed="$(new_progress_lines)"
  if [ "$progressed" -gt 0 ]; then
    # Real traffic is generating. Nothing to prove, nothing to ask for.
    clear_progress_state
    return 0
  fi

  if endpoint_busy; then
    echo "cluster-peer: request in flight on :${CLUSTER_HTTP_PORT:-?}; deferring the probe"
    return 0
  fi

  now="$(date +%s)"
  last="$(read_int "$probed_file")"
  [ "$((now - last))" -ge "$probe_interval" ] || return 0
  printf '%s\n' "$now" > "$probed_file"

  if probe_tokens; then
    rm -f "$strikes_file"
    return 0
  fi

  strikes="$(($(read_int "$strikes_file") + 1))"
  printf '%s\n' "$strikes" > "$strikes_file"
  if [ "$strikes" -lt "$max_strikes" ]; then
    echo "cluster-peer: bounded probe produced no token ($strikes/$max_strikes)"
    return 0
  fi

  # Classify before tearing down, so the page says WHICH failure this is.
  local probes="$strikes consecutive bounded probes produced no token (${CLUSTER_PEER_PROBE_TIMEOUT_SECS:-120}s each)"
  if ! peer_reachable; then
    cause="$probes and the peer stopped answering ping: peer host or link is down"
    evidence="peer=${CLUSTER_STATIC_PEER_IP} ping=failed"
  elif peer_rendezvous_session; then
    cause="$probes while the peer answers ping and the JACCL rendezvous session is still open: the peer rank is WEDGED and rank 0 is blocked in recv behind it"
    evidence="peer=${CLUSTER_STATIC_PEER_IP} ping=ok rendezvous=established"
  else
    cause="$probes; the peer answers ping but its JACCL rendezvous session is GONE: the peer rank process died. Its traceback is in the peer's own rank log — the worker pages that separately"
    evidence="peer=${CLUSTER_STATIC_PEER_IP} ping=ok rendezvous=absent"
  fi
  escalate "$cause" "$evidence"
}

# Worker: rank 1 never binds the endpoint, so it cannot see a token. It reports
# the one thing only it can — its own rank dying — and attaches the traceback,
# which is the evidence the coordinator can never obtain.
#
# The page waits CLUSTER_PEER_DEAD_TICKS so the watcher's own kickstart retries
# are not paged over, and fires once per death episode; a rank that comes back
# re-arms it.
worker_tick() {
  local dead fault
  if rank_running; then
    rm -f "$dead_file" "$reported_file"
    return 0
  fi
  dead="$(($(read_int "$dead_file") + 1))"
  printf '%s\n' "$dead" > "$dead_file"
  [ "$dead" -ge "$dead_ticks_max" ] || return 0
  [ -f "$reported_file" ] && return 0
  touch "$reported_file"

  fault="$(rank_fault_line)"
  echo "cluster-peer: worker rank down for $dead consecutive ticks with the link up${fault:+ — $fault}" >&2
  CLUSTER_ALERT_PREFIX=":rotating_light: *mlx-cluster worker rank down*" \
    alert "$host (worker): rank agent $rank_label is not running, $dead ticks after the link came up.
The coordinator CANNOT see this: it blocks in jaccl recv while its endpoint keeps answering 200.
${fault:-no exception line matched in the rank logs}
--- worker rank log tail ---
$(log_tail)"

  # Only restore standalone serving once the watcher has given up (halt marker
  # present). While it is still retrying kickstarts this node is meant to come
  # back as a rank, and restoring underneath it would fight the watcher.
  if [ -f "$halt_file" ]; then
    if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
      set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
    fi
    restore_normal_serving || true
  fi
}

main() {
  # Link down: not clustered, nothing to supervise. The watcher owns that
  # transition and has already restored standalone serving.
  if ! link_up; then
    reset_state
    return 0
  fi

  if [ "$role" = "worker" ]; then
    worker_tick
    return 0
  fi

  # Coordinator. Two supervisors killing one process is worse than a late
  # detection, so stand down wherever the watcher already owns the rank: a rank
  # that is not running belongs to its kickstart/PD-guard path, a rank that has
  # not latched readiness belongs to its load-grace path, and a rank behind the
  # halt marker has already been torn down by one of us.
  if [ -f "$halt_file" ] || ! rank_running || [ ! -f "$ready_file" ]; then
    clear_progress_state
    return 0
  fi
  coordinator_tick
}

main "$@"
