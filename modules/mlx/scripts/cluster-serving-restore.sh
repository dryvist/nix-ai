# shellcheck shell=bash
# Bring standalone (non-clustered) serving back — the ONE definition.
#
# Shared by cluster-join recovery and cluster-detach.
# Before that split, detach carried a coordinator-only copy of half of it and no
# worker path at all: on a worker it downed the link, verified markers/rank/
# ceiling, printed "teardown verified" — and left every agent cluster-quiesce
# had booted out still booted out, with nothing serving on the host. "Standalone
# ceiling restored" is not "serving restored", and the only way those two can
# never be confused again is for the restore to be the same function on every
# path that claims it.
#
# Consumers: cluster-join's failure trap and cluster-detach teardown.
#
# Consumed environment:
#   CLUSTER_ROLE          coordinator | worker
#   CLUSTER_SERVER_LABELS / CLUSTER_LAUNCH_AGENTS_DIR
#   coordinator: CLUSTER_WATCHDOG_LABEL / CLUSTER_WATCHDOG_PLIST (optional)
#   worker:      CLUSTER_RESTORE_CMD  (restores the agent set cluster-quiesce recorded)
cluster_launchd_label_disabled() {
  local label="$1" launchctl_bin="${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" listing state="" key arrow value
  listing="$("$launchctl_bin" print-disabled "gui/$(id -u)" 2> /dev/null)" || return 2
  while read -r key arrow value; do
    if [ "$arrow" = "=>" ] && [ "${key//\"/}" = "$label" ]; then
      state="$value"
      break
    fi
  done <<< "$listing"
  case "$state" in
    disabled) return 0 ;;
    enabled | '') return 1 ;;
    *) return 2 ;;
  esac
}

cluster_launchd_label_loaded() {
  "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" print "gui/$(id -u)/$1" > /dev/null 2>&1
}

cluster_launchd_label_declared() {
  local target="$1" label
  local -a labels=()
  IFS=' ' read -r -a labels <<< "${CLUSTER_DECLARED_AGENT_LABELS:-}"
  for label in "${labels[@]}"; do
    [ "$label" = "$target" ] && return 0
  done
  return 1
}

cluster_restore_launchd_agent() {
  local label="$1" plist="$2" uid="$3" launchctl_bin="${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" disabled_rc
  if cluster_launchd_label_disabled "$label"; then
    disabled_rc=0
  else
    disabled_rc=$?
    if [ "$disabled_rc" -eq 2 ]; then
      echo "cluster-link: WARN cannot read launchd disabled state for $label" >&2
      return 1
    fi
  fi
  if [ "$disabled_rc" -eq 0 ] || ! cluster_launchd_label_loaded "$label"; then
    if ! "$launchctl_bin" enable "gui/$uid/$label" > /dev/null 2>&1; then
      echo "cluster-link: WARN failed to enable $label" >&2
      return 1
    fi
    if [ "$disabled_rc" -eq 0 ] && cluster_launchd_label_loaded "$label"; then
      if ! "$launchctl_bin" kickstart "gui/$uid/$label" > /dev/null 2>&1; then
        echo "cluster-link: WARN failed to kickstart $label" >&2
        return 1
      fi
      echo "cluster-link: $label enabled and kickstarted"
      return 0
    fi
    if [ ! -f "$plist" ]; then
      echo "cluster-link: WARN $label not loaded and no plist to bootstrap" >&2
      return 1
    fi
    echo "cluster-link: $label not loaded; bootstrapping"
    if ! "$launchctl_bin" bootstrap "gui/$uid" "$plist" > /dev/null 2>&1; then
      echo "cluster-link: WARN failed to bootstrap $label" >&2
      return 1
    fi
  fi
}

# Returns nonzero if it could not restore, so the lifecycle command can fail
# its postcondition and report which standalone service did not return.
restore_normal_serving() {
  local uid server_label server_plist watchdog_plist
  local -a server_labels=()
  uid="$(id -u)"
  read -r -a server_labels <<< "${CLUSTER_SERVER_LABELS:-}"
  for server_label in "${server_labels[@]}"; do
    server_plist="${CLUSTER_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/$server_label.plist"
    cluster_restore_launchd_agent "$server_label" "$server_plist" "$uid" || return 1
  done
  if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -n "${CLUSTER_WATCHDOG_LABEL:-}" ]; then
    watchdog_plist="${CLUSTER_WATCHDOG_PLIST:-${CLUSTER_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/$CLUSTER_WATCHDOG_LABEL.plist}"
    cluster_restore_launchd_agent "$CLUSTER_WATCHDOG_LABEL" "$watchdog_plist" "$uid" || return 1
  fi
  if [ "$CLUSTER_ROLE" = "worker" ] && [ -n "${CLUSTER_RESTORE_CMD:-}" ]; then
    # The worker hook restores additional agents recorded by its quiesce hook.
    "${CLUSTER_SH_BIN:-/bin/sh}" -c "$CLUSTER_RESTORE_CMD" || return 1
  elif [ "$CLUSTER_ROLE" = "worker" ] && [ -n "${CLUSTER_QUIESCE_CMD:-}" ]; then
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
