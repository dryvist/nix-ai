# shellcheck shell=bash
# Daytime agent body, coordinator only. When this host is clustered, it runs the
# existing detach. Otherwise it logs the hold and exits 0. It never reboots and
# never retries. A detach exit 3 is logged and propagated.

# D2: launchd must still hold each standalone serving label, or detach cannot
# restore serving. A cluster quiesce boots these labels out, so a check for loaded
# labels would fail every time while clustered. The check is restorability instead:
# a plist is present to bootstrap, or the label is loaded, and launchd can read the
# disabled state. It mirrors the preconditions of cluster_restore_launchd_agent
# in cluster-serving-restore.sh.
schedule_serving_loadable() {
  local launchctl_bin="${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" uid label plist missing=""
  local -a labels=()
  uid="$(id -u)"
  read -r -a labels <<< "${CLUSTER_SERVER_LABELS:-}"
  if [ -n "${CLUSTER_WATCHDOG_LABEL:-}" ]; then
    labels+=("$CLUSTER_WATCHDOG_LABEL")
  fi
  if ! "$launchctl_bin" print-disabled "gui/$uid" > /dev/null 2>&1; then
    schedule_log D2 hold serving-state-unreadable
    return 1
  fi
  for label in "${labels[@]}"; do
    [ -n "$label" ] || continue
    plist="${CLUSTER_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/$label.plist"
    if [ -f "$plist" ] || "$launchctl_bin" print "gui/$uid/$label" > /dev/null 2>&1; then
      continue
    fi
    missing="$missing $label"
  done
  if [ -n "$missing" ]; then
    echo "cluster-schedule: D2 detail=no plist and not loaded:$missing"
    schedule_log D2 hold serving-label-unloadable
    return 1
  fi
  schedule_log D2 pass serving-labels-loadable
  return 0
}

schedule_daytime_main() {
  local rc=0
  echo "cluster-schedule: daytime start CLUSTER_INVOKER=${CLUSTER_INVOKER:-manual}"
  if schedule_clustered; then
    schedule_log D1 pass clustered
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      schedule_log D1 hold not-clustered
      return 0
    fi
    echo "cluster-schedule: D1 detail=$SCHEDULE_CLUSTER_DETAIL"
    schedule_log D1 hold mode-unanswerable
    return 1
  fi
  schedule_serving_loadable || return 1
  echo "cluster-schedule: daytime decision=detach"
  if "$CLUSTER_DETACH_BIN"; then
    echo "cluster-schedule: daytime detach rc=0"
    return 0
  else
    rc=$?
  fi
  if [ "$rc" -eq 3 ]; then
    echo "cluster-schedule: daytime detach rc=3 reason=reboot-required; not rebooting, not retrying"
    return 3
  fi
  echo "cluster-schedule: daytime detach rc=$rc reason=detach-failed; not retrying"
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  schedule_daytime_main "$@"
fi
