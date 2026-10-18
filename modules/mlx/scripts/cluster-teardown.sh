# shellcheck shell=bash
# Shared fail-closed teardown for cluster-join recovery and cluster-detach.

export TEARDOWN_FAILED TEARDOWN_REBOOT TEARDOWN_SIGKILLED

cluster_lifecycle_log_start() {
  mkdir -p "$(dirname "$CLUSTER_LIFECYCLE_LOG")"
  exec > >(tee -a "$CLUSTER_LIFECYCLE_LOG") 2>&1
}

lifecycle_refuse() {
  local reason="$1" detail="$2" component="${CLUSTER_LIFECYCLE_COMPONENT:-cluster-lifecycle}"
  detail="${detail//$'\n'/ }"
  detail="${detail//$'\r'/ }"
  printf '%s: REFUSE reason=%s detail=%s\n' "$component" "$reason" "$detail" >&2
}

cluster_lifecycle_lock_acquire() {
  local lock="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_PEER_STATE_FILE")}/cluster-lifecycle.lock" owner
  if mkdir "$lock" 2> /dev/null; then
    if ! printf '%s\n' "$BASHPID" > "$lock/pid"; then
      rmdir "$lock" 2> /dev/null || true
      return 1
    fi
    CLUSTER_LIFECYCLE_LOCK_PATH="$lock"
    CLUSTER_LIFECYCLE_LOCK_PID="$BASHPID"
    return 0
  fi
  if [ -f "$lock/pid" ]; then
    owner="$(cat "$lock/pid" 2> /dev/null || true)"
    case "$owner" in
      '' | *[!0-9]*) return 1 ;;
    esac
    if kill -0 "$owner" 2> /dev/null; then
      return 1
    fi
    rm -f "$lock/pid" 2> /dev/null || return 1
    rmdir "$lock" 2> /dev/null || return 1
    if mkdir "$lock" 2> /dev/null; then
      if ! printf '%s\n' "$BASHPID" > "$lock/pid"; then
        rmdir "$lock" 2> /dev/null || true
        return 1
      fi
      CLUSTER_LIFECYCLE_LOCK_PATH="$lock"
      CLUSTER_LIFECYCLE_LOCK_PID="$BASHPID"
      return 0
    fi
  fi
  return 1
}

cluster_lifecycle_lock_release() {
  local owner
  [ -n "${CLUSTER_LIFECYCLE_LOCK_PATH:-}" ] || return 0
  owner="$(cat "$CLUSTER_LIFECYCLE_LOCK_PATH/pid" 2> /dev/null || true)"
  if [ "$owner" = "${CLUSTER_LIFECYCLE_LOCK_PID:-}" ]; then
    rm -f "$CLUSTER_LIFECYCLE_LOCK_PATH/pid"
    rmdir "$CLUSTER_LIFECYCLE_LOCK_PATH" 2> /dev/null || true
  fi
  CLUSTER_LIFECYCLE_LOCK_PATH=""
  CLUSTER_LIFECYCLE_LOCK_PID=""
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
    if [ "$rc" -ne 0 ]; then
      lifecycle_refuse quiesced-agent-restore-failed "could not restore $label (rc=$rc)"
      TEARDOWN_FAILED=1
    fi
  done < "$agents_file"
  : > "$agents_file"
}

cluster_teardown() {
  local count_rc=0 session="${1:-}" disarm_failed=false
  TEARDOWN_FAILED=0
  TEARDOWN_REBOOT=0
  TEARDOWN_SIGKILLED=0
  if [ -z "$session" ] && [ -f "${CLUSTER_PEER_STATE_FILE:-}" ]; then
    session="$(jq -r '.session // ""' "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || true)"
  fi
  if peer_state_write false 0 "$session" abort; then
    echo "cluster-teardown: peer state disarmed for session=${session:-none}"
  else
    lifecycle_refuse disarm-failed "could not write peer phase abort for session=${session:-none}"
    disarm_failed=true
    TEARDOWN_FAILED=1
  fi
  if ! rm -f "${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_PEER_STATE_FILE")}/rank-model"; then
    lifecycle_refuse teardown-state-remove-failed "could not remove rank-model state"
    TEARDOWN_FAILED=1
  fi
  if ! rank_process_absent; then
    if ! rank_stop_verified || ! rank_process_absent; then
      lifecycle_refuse rank-survivor "rank absence is unverified; serving and link-state stay unchanged"
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
    lifecycle_refuse pd-count-unreadable "PD count rc=$count_rc; the next join's J1 will refuse if the count remains unreadable"
    TEARDOWN_FAILED=1
  fi
  if set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}"; then
    echo "cluster-teardown: standalone wired ceiling restored"
  else
    lifecycle_refuse wired-ceiling-restore-failed "standalone wired ceiling restore failed"
    TEARDOWN_FAILED=1
  fi
  if restore_normal_serving; then
    echo "cluster-teardown: standalone serving restore issued"
  else
    lifecycle_refuse serving-restore-failed "standalone serving restore failed"
    TEARDOWN_FAILED=1
  fi
  cluster_restore_quiesced_agents
  if [ "$disarm_failed" = true ]; then
    echo "cluster-teardown: link-state left unchanged because peer disarm failed"
  elif link_state_write down; then
    echo "cluster-teardown: link-state down"
  else
    lifecycle_refuse link-state-write-failed "could not write link-state down"
    TEARDOWN_FAILED=1
  fi
  return "$TEARDOWN_FAILED"
}
