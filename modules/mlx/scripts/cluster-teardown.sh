# shellcheck shell=bash
# Shared fail-closed teardown for cluster-join recovery and cluster-detach.

export TEARDOWN_FAILED TEARDOWN_REBOOT TEARDOWN_SIGKILLED

cluster_lifecycle_log_start() {
  mkdir -p "$(dirname "$CLUSTER_LIFECYCLE_LOG")"
  exec > >(tee -a "$CLUSTER_LIFECYCLE_LOG") 2>&1
}

cluster_restore_quiesced_agents() {
  local uid label plist rc agents_file="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_PEER_STATE_FILE")}/quiesced-agents"
  [ -f "$agents_file" ] || return 0
  uid="$(id -u)"
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    plist="${CLUSTER_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/$label.plist"
    if [ -f "$plist" ]; then
      if "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" bootstrap "gui/$uid" "$plist" > /dev/null 2>&1; then
        rc=0
      else
        rc=$?
      fi
    elif "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" kickstart "gui/$uid/$label" > /dev/null 2>&1; then
      rc=0
    else
      rc=$?
    fi
    echo "cluster-teardown: quiesce restore $label rc=$rc"
    [ "$rc" -eq 0 ] || TEARDOWN_FAILED=1
  done < "$agents_file"
  : > "$agents_file"
}

cluster_teardown() {
  local count_rc=0
  TEARDOWN_FAILED=0
  TEARDOWN_REBOOT=0
  TEARDOWN_SIGKILLED=0
  if peer_state_write false 0; then
    echo "cluster-teardown: peer state disarmed"
  else
    echo "cluster-teardown: FAIL could not disarm peer state" >&2
    TEARDOWN_FAILED=1
  fi
  if ! rank_process_absent; then
    if ! rank_stop_verified || ! rank_process_absent; then
      echo "cluster-teardown: FAIL rank absence is unverified; serving and link-state stay unchanged" >&2
      return 1
    fi
  fi
  if pd_held_count; then
    echo "cluster-teardown: PD held=$PD_HELD budget=${CLUSTER_PD_DEVICE_BUDGET:-?} with no rank alive"
    if [ "$PD_HELD" -gt 0 ]; then
      TEARDOWN_REBOOT=1
      echo "cluster-teardown: $PD_HELD of ${CLUSTER_PD_DEVICE_BUDGET:-?} PDs held with no rank alive; reboot before the next join" >&2
    fi
  else
    count_rc=$?
    echo "cluster-teardown: PD held=UNKNOWN rc=$count_rc; the next join's J1 will refuse if the count remains unreadable" >&2
    TEARDOWN_FAILED=1
  fi
  if set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}"; then
    echo "cluster-teardown: standalone wired ceiling restored"
  else
    echo "cluster-teardown: FAIL standalone wired ceiling restore failed" >&2
    TEARDOWN_FAILED=1
  fi
  if restore_normal_serving; then
    echo "cluster-teardown: standalone serving restore issued"
  else
    echo "cluster-teardown: FAIL standalone serving restore failed" >&2
    TEARDOWN_FAILED=1
  fi
  cluster_restore_quiesced_agents
  if link_state_write down; then
    echo "cluster-teardown: link-state down"
  else
    echo "cluster-teardown: FAIL could not write link-state down" >&2
    TEARDOWN_FAILED=1
  fi
  return "$TEARDOWN_FAILED"
}
