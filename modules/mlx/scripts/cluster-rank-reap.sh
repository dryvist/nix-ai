# shellcheck shell=bash
# The graceful rank reap — SIGTERM, then PROVE it worked.

export TEARDOWN_SIGKILLED TEARDOWN_REBOOT
#
# Concatenated after ./cluster-rank-status.sh for the shared join-failure and
# detach teardown. Both paths use the same process-level proof of rank absence.
#
# WHY A PROCESS-LEVEL SIGTERM AND NOT JUST `launchctl kill`. launchd signals the
# JOB. An engine that has been re-parented — orphaned by a killed supervisor, or
# surviving a bootout — is no longer part of that job, so the signal reaches
# nothing while `launchctl print` happily reports the label as stopped. That
# survivor still owns its protection domain. Signalling the pid directly is what
# actually reaches it.
#
# WHY THIS PROVES ANYTHING. A protection domain is held by a PROCESS, not by
# damaged kernel state. Measured: reaping two leaked worker processes changed the
# next rank start's failure from errno 96 (protection domains exhausted) to
# errno 60 (couldn't connect) — the domains came back the moment their owners
# died. So "no rank process is alive" is a sufficient condition for the domains
# being available, and enforcing it before every start is what makes accumulation
# impossible rather than merely unlikely.
#
# rank_reap_verified uses SIGTERM only. rank_stop_verified owns the audited
# SIGKILL fallback for an operator teardown; it marks the host reboot-required
# and the kernel count confirms whether any domains remain held.
#
# $1 optional grace seconds (default CLUSTER_RANK_REAP_GRACE_SECS, then 30).
rank_reap_verified() {
  local grace="${1:-${CLUSTER_RANK_REAP_GRACE_SECS:-30}}" pids pid deadline
  if [ -z "${CLUSTER_RANK_PROCESS_PATTERN:-}" ]; then
    echo "cluster: CLUSTER_RANK_PROCESS_PATTERN is unset — refusing to assume no previous rank survives" >&2
    return 1
  fi
  if rank_process_absent; then
    return 0
  fi
  pids="$(rank_process_pids || true)"
  if [ -z "$pids" ]; then
    # Not proven absent, yet no pids came back: pgrep itself could not answer.
    echo "cluster: could not determine whether a rank process survives (${CLUSTER_PGREP_BIN:-/usr/bin/pgrep} unusable) — refusing to treat that as 'nothing to clean up'" >&2
    return 1
  fi
  echo "cluster: a rank process is STILL RUNNING ($(printf '%s' "$pids" | tr '\n' ' ')) and still owns its RDMA protection domain; SIGTERM, then re-verify" >&2
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    "${CLUSTER_KILL_BIN:-/bin/kill}" -TERM "$pid" > /dev/null 2>&1 || true
  done <<< "$pids"
  deadline=$(($(date +%s) + grace))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 2
    if rank_process_absent; then
      echo "cluster: rank exited on SIGTERM and released its protection domain"
      return 0
    fi
  done
  echo "cluster: rank survived SIGTERM for ${grace}s and still holds its protection domain" >&2
  return 1
}

# Stop a rank for an operator teardown. SIGKILL is the audited last resort and
# makes a reboot mandatory even when the process is subsequently absent.
rank_stop_verified() {
  local uid pkill_bin="${CLUSTER_PKILL_BIN:-/usr/bin/pkill}"
  uid="$(id -u)"
  TEARDOWN_SIGKILLED=0
  if rank_process_absent; then
    echo "cluster-teardown: rank already absent"
    return 0
  fi
  "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" kill SIGTERM \
    "gui/$uid/${CLUSTER_RANK_LABEL}" > /dev/null 2>&1 || true
  if rank_reap_verified "${CLUSTER_DETACH_TIMEOUT_SECS:-300}"; then
    return 0
  fi
  echo "cluster-teardown: rank survived SIGTERM; escalating to SIGKILL" >&2
  "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" kill SIGKILL \
    "gui/$uid/${CLUSTER_RANK_LABEL}" > /dev/null 2>&1 || true
  if [ -n "${CLUSTER_RANK_PROCESS_PATTERN:-}" ]; then
    "$pkill_bin" -9 -f "$CLUSTER_RANK_PROCESS_PATTERN" > /dev/null 2>&1 || true
  else
    echo "cluster-teardown: CLUSTER_RANK_PROCESS_PATTERN unset; skipped pattern kill" >&2
  fi
  sleep 3
  if rank_process_absent; then
    TEARDOWN_SIGKILLED=1
    TEARDOWN_REBOOT=1
    return 0
  fi
  echo "cluster-teardown: FAIL rank remains after SIGKILL" >&2
  TEARDOWN_SIGKILLED=1
  TEARDOWN_REBOOT=1
  return 1
}
