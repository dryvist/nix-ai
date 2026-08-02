# shellcheck shell=bash
# Bring standalone (non-clustered) serving back — the ONE definition.
#
# Split out of ./cluster-link-helpers.sh so cluster-detach can call it too.
# Before that split, detach carried a coordinator-only copy of half of it and no
# worker path at all: on a worker it downed the link, verified markers/rank/
# ceiling, printed "teardown verified", exited 0 — and left every agent
# cluster-quiesce had booted out still booted out, with nothing serving on the
# host. Observed 2026-08-01 (86h). "Standalone ceiling restored" is not
# "serving restored", and the only way those two can never be confused again is
# for the restore to be the same function on every path that claims it.
#
# Consumers: the link watcher (up->down edge, PD-guard halt, wedge teardown),
# the peer-liveness supervisor, and cluster-detach.
#
# Returns nonzero if it could not restore, so the caller can decline to consume
# a link-state edge, or fail its own postcondition, and retry.
#
# Consumed environment:
#   CLUSTER_ROLE          coordinator | worker
#   coordinator: CLUSTER_SERVER_LABEL / CLUSTER_SERVER_PLIST / CLUSTER_WARMUP_LABEL
#   worker:      CLUSTER_RESTORE_CMD  (cluster-restore — bootstraps back exactly
#                the agent set cluster-quiesce recorded, never a hardcoded list)
restore_normal_serving() {
  local uid
  uid="$(id -u)"
  if [ "$CLUSTER_ROLE" = "coordinator" ]; then
    # INC-17071: the warmup one-shot re-warms the preload list by POSTing to
    # llama-swap over loopback, so if the server agent is not loaded the
    # kickstart hits nothing and no-ops SILENTLY -- serving never comes back.
    # cluster-join boots that agent out, so any session that used it left the
    # unattended cable-yank path unable to restore. Bootstrap it first.
    if [ -n "${CLUSTER_SERVER_LABEL:-}" ] &&
      ! launchctl print "gui/$uid/$CLUSTER_SERVER_LABEL" > /dev/null 2>&1; then
      if [ ! -f "${CLUSTER_SERVER_PLIST:-}" ]; then
        echo "cluster-link: WARN $CLUSTER_SERVER_LABEL not loaded and no plist to bootstrap" >&2
        return 1
      fi
      echo "cluster-link: standalone server agent not loaded; bootstrapping"
      if ! launchctl bootstrap "gui/$uid" "$CLUSTER_SERVER_PLIST" > /dev/null 2>&1; then
        echo "cluster-link: WARN failed to bootstrap $CLUSTER_SERVER_LABEL" >&2
        return 1
      fi
    fi
    # Re-warm the declared preload list through the existing warmup one-shot.
    launchctl kickstart -k "gui/$uid/$CLUSTER_WARMUP_LABEL" || true
  elif [ -n "${CLUSTER_RESTORE_CMD:-}" ]; then
    # cluster-restore keeps the labels it could not bootstrap and exits nonzero
    # precisely so a later tick retries them; propagate that.
    sh -c "$CLUSTER_RESTORE_CMD" || return 1
  elif [ -n "${CLUSTER_QUIESCE_CMD:-}" ]; then
    # THIS host takes serving away on every join and has no way to give it back.
    # Saying so is the whole point: the silent `return 0` this replaced is what
    # let cluster-detach report success over a machine serving nothing. The
    # config that produces it is also refused at eval (cluster-assertions.nix);
    # this is the runtime half of the same invariant.
    echo "cluster-link: WARN role=$CLUSTER_ROLE quiesces serving but has no CLUSTER_RESTORE_CMD; standalone serving CANNOT be restored by this host" >&2
    return 1
  fi
  # Neither hook configured: this host never quiesces anything, so there is
  # nothing to restore and nothing to report. Success, because the requested
  # end state holds — not because the request was ignored.
}
