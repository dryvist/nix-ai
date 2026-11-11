# shellcheck shell=bash
# Daytime agent body, coordinator only. When this host is clustered, or holds a
# deferred restore whose rank has exited, it runs the existing detach. When this
# host is standalone but the worker is still armed or holds a deferred restore,
# it retries the worker detach, at most once per run and three runs per worker
# session. Otherwise it logs the hold and exits 0. It never reboots. A detach
# exit 3 is logged and propagated.

# D3: a worker left clustered by a failed peer detach. The coordinator has
# already torn itself down, so D1 says not-clustered; the worker's own peer state
# says whether it still needs a detach. The count lives in the state directory as
# "<worker session> <attempts>", or "<worker session> reboot" after an exit 3.
schedule_guard_peer_detach() {
  local retry_file armed phase session reason recorded="" count="" rc=0
  retry_file="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_PEER_STATE_FILE")}/peer-detach-retry"
  if ! peer_state_fetch; then
    schedule_log D3 hold peer-unreachable
    return 0
  fi
  armed="$(jq -r '.armed // false' <<< "$PEER_STATE_RAW")"
  phase="$(jq -r '.phase // ""' <<< "$PEER_STATE_RAW")"
  session="$(jq -r '.session // ""' <<< "$PEER_STATE_RAW")"
  if [ "$armed" = true ]; then
    reason=peer-armed
  elif [ "$phase" = restore-pending ]; then
    reason=peer-restore-pending
  else
    rm -f "$retry_file"
    schedule_log D3 pass peer-standalone
    return 0
  fi
  session="${session:-none}"
  read -r recorded count < "$retry_file" 2> /dev/null || true
  [ "$recorded" = "$session" ] || count=0
  if [ "$count" = reboot ]; then
    schedule_log D3 hold peer-reboot-required
    return 0
  fi
  case "$count" in '' | *[!0-9]*) count=0 ;; esac
  if [ "$count" -ge 3 ]; then
    schedule_log D3 hold peer-retry-exhausted
    return 0
  fi
  count=$((count + 1))
  printf '%s %s\n' "$session" "$count" > "$retry_file"
  schedule_log D3 retry "$reason attempt=$count/3"
  "$CLUSTER_DETACH_BIN" --peer || rc=$?
  if [ "$rc" -eq 3 ]; then
    printf '%s reboot\n' "$session" > "$retry_file"
    schedule_log D3 hold peer-reboot-required
    return 3
  fi
  echo "cluster-schedule: daytime peer detach rc=$rc"
  return "$rc"
}

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
  # D0: a deferred restore. Detach finishes it once the rank has exited; while
  # the rank lives, a detach would only repeat the stop that already failed.
  if [ -f "$(rank_restore_pending_file)" ]; then
    if rank_process_running; then
      schedule_log D0 hold rank-survivor-pending
      return 0
    fi
    if ! rank_process_absent; then
      schedule_log D0 hold rank-probe-unanswerable
      return 1
    fi
    schedule_log D0 pass finish-restore
  elif schedule_clustered; then
    schedule_log D1 pass clustered
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      schedule_log D1 hold not-clustered
      schedule_guard_peer_detach
      return
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
