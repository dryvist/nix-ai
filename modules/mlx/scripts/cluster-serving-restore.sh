# shellcheck shell=bash
# Bring standalone (non-clustered) serving back — the ONE definition.
#
# Split out of ./cluster-link-helpers.sh so cluster-detach can call it too.
# Before that split, detach carried a coordinator-only copy of half of it and no
# worker path at all: on a worker it downed the link, verified markers/rank/
# ceiling, printed "teardown verified", exited 0 — and left every agent
# cluster-quiesce had booted out still booted out, with nothing serving on the
# host. "Standalone ceiling restored" is not "serving restored", and the only
# way those two can never be confused again is for the restore to be the same
# function on every path that claims it.
#
# Consumers: the link watcher (up->down edge, PD-guard halt, wedge teardown),
# the peer-liveness supervisor, and cluster-detach.
#
# Returns nonzero if it could not restore, so the caller can decline to consume
# a link-state edge, or fail its own postcondition, and retry.
#
# Consumed environment:
#   CLUSTER_ROLE          coordinator | worker
#   coordinator: CLUSTER_SERVER_LABELS / CLUSTER_LAUNCH_AGENTS_DIR
#                CLUSTER_WATCHDOG_LABEL / CLUSTER_WATCHDOG_PLIST (optional — an
#                older generation without them just skips the watchdog restore)
#   worker:      CLUSTER_RESTORE_CMD  (cluster-restore — bootstraps back exactly
#                the agent set cluster-quiesce recorded, never a hardcoded list)
restore_normal_serving() {
  local uid
  uid="$(id -u)"
  if [ "$CLUSTER_ROLE" = "coordinator" ]; then
    # cluster-join boots the resident agents out, so every absent resident must
    # be bootstrapped from its own plist before standalone serving is restored.
    local server_label server_plist
    local -a server_labels=()
    read -r -a server_labels <<< "${CLUSTER_SERVER_LABELS:-}"
    for server_label in "${server_labels[@]}"; do
      if ! launchctl print "gui/$uid/$server_label" > /dev/null 2>&1; then
        server_plist="${CLUSTER_LAUNCH_AGENTS_DIR:-}/$server_label.plist"
        if [ ! -f "$server_plist" ]; then
          echo "cluster-link: WARN $server_label not loaded and no plist to bootstrap" >&2
          return 1
        fi
        echo "cluster-link: standalone server agent not loaded; bootstrapping"
        if ! launchctl bootstrap "gui/$uid" "$server_plist" > /dev/null 2>&1; then
          echo "cluster-link: WARN failed to bootstrap $server_label" >&2
          return 1
        fi
      fi
    done
    # The serving watchdog is booted out alongside the resident agents above (see
    # cluster-join), so it needs the same bootstrap-back treatment. Best-effort:
    # standalone serving itself is
    # already restored by this point, so a watchdog that cannot come back is a
    # missing safety net, not a repeat of the outage this function exists to fix.
    if [ -z "${CLUSTER_WATCHDOG_LABEL:-}" ]; then
      echo "cluster-link: no CLUSTER_WATCHDOG_LABEL configured; nothing to restore for the watchdog"
    elif launchctl print "gui/$uid/$CLUSTER_WATCHDOG_LABEL" > /dev/null 2>&1; then
      echo "cluster-link: $CLUSTER_WATCHDOG_LABEL already loaded"
    elif [ -f "${CLUSTER_WATCHDOG_PLIST:-}" ]; then
      echo "cluster-link: watchdog agent not loaded; bootstrapping"
      if launchctl bootstrap "gui/$uid" "$CLUSTER_WATCHDOG_PLIST" > /dev/null 2>&1; then
        echo "cluster-link: $CLUSTER_WATCHDOG_LABEL bootstrapped"
      else
        echo "cluster-link: WARN failed to bootstrap $CLUSTER_WATCHDOG_LABEL" >&2
      fi
    else
      echo "cluster-link: WARN $CLUSTER_WATCHDOG_LABEL not loaded and no plist to bootstrap" >&2
    fi
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
