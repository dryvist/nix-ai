# shellcheck shell=bash
# The graceful rank reap — SIGTERM, then PROVE it worked.
#
# Concatenated after ./cluster-rank-status.sh into the two consumers that stop
# ranks: the link watcher (as a hard precondition before any start) and
# cluster-detach (as the phase that must fail before SIGKILL is even considered).
# One implementation, so the daily unplug path and the unattended restart path
# cannot drift into two different ideas of "the rank is gone".
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
# SIGTERM ONLY, DELIBERATELY. A SIGKILL here would leak the very domain the
# function exists to protect, so a survivor that ignores SIGTERM is reported and
# the caller refuses. Refusing costs nothing — no distributed init runs, so no
# domain is spent — and is retried on the next tick. Escalating costs a reboot.
# cluster-detach is the one caller allowed to escalate afterwards, and it pays
# for it by writing the loss to the ledger.
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
