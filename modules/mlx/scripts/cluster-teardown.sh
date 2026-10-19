# shellcheck shell=bash
# Shared fail-closed teardown for cluster-join recovery and cluster-detach.

export TEARDOWN_FAILED TEARDOWN_REBOOT TEARDOWN_SIGKILLED CLUSTER_PEER_SSH_RC

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

cluster_peer_ssh_running() {
  local pid expected="${1:-${CLUSTER_PEER_SSH_PID:-}}"
  [ -n "$expected" ] || return 1
  while IFS= read -r pid; do
    [ "$pid" = "$expected" ] && return 0
  done < <(jobs -pr)
  return 1
}

cluster_peer_ssh_wait() {
  local pid="${1:-${CLUSTER_PEER_SSH_PID:-}}"
  local timeout="${2:-${CLUSTER_JOIN_TIMEOUT_SECS:-600}}"
  local timeout_reason="${3:-peer-ssh-timeout}"
  local ignore_signal="${4:-false}"
  local deadline term_deadline reap_deadline rc timed_out=false
  [ -n "$pid" ] || return 0
  deadline=$((SECONDS + timeout))
  while cluster_peer_ssh_running "$pid"; do
    if [ "${JOIN_SIGNAL_RC:-0}" -ne 0 ] && [ "$ignore_signal" != true ]; then
      echo "cluster-lifecycle: peer-ssh stopping after signal rc=$JOIN_SIGNAL_RC" >&2
      break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      timed_out=true
      echo "cluster-lifecycle: peer-ssh timeout" >&2
      break
    fi
    sleep 1
  done
  if cluster_peer_ssh_running "$pid"; then
    kill -TERM "$pid" 2> /dev/null || true
    term_deadline=$((SECONDS + 5))
    while cluster_peer_ssh_running "$pid" && [ "$SECONDS" -lt "$term_deadline" ]; do sleep 1; done
    if cluster_peer_ssh_running "$pid"; then
      kill -KILL "$pid" 2> /dev/null || true
      reap_deadline=$((SECONDS + 10))
      while cluster_peer_ssh_running "$pid" && [ "$SECONDS" -lt "$reap_deadline" ]; do sleep 1; done
      if cluster_peer_ssh_running "$pid"; then
        CLUSTER_PEER_SSH_RC=1
        lifecycle_refuse peer-ssh-reap-uncertain \
          "could not confirm worker ssh pid=$pid exited within 10s after SIGKILL"
        return 1
      fi
    fi
  fi
  if wait "$pid"; then rc=0; else rc=$?; fi
  CLUSTER_PEER_SSH_RC=$rc
  if [ "${CLUSTER_PEER_SSH_PID:-}" = "$pid" ]; then CLUSTER_PEER_SSH_PID=""; fi
  echo "cluster-lifecycle: peer-ssh exit rc=$rc"
  if [ "$timed_out" = true ]; then
    CLUSTER_PEER_SSH_RC=124
    lifecycle_refuse "$timeout_reason" "worker ssh exceeded the ${timeout}s deadline"
    return 1
  fi
}

cluster_lifecycle_lock_record() {
  local lock="$1" boot owner="$BASHPID"
  boot="$(current_boot_epoch)"
  case "$boot" in '' | *[!0-9]*) boot=0 ;; esac
  # The exclusive pid create is the ownership claim; a late writer whose directory was reclaimed loses here.
  if ! (set -C && printf '%s\n' "$owner" > "$lock/pid") 2> /dev/null; then
    return 1
  fi
  if ! printf '%s\n' "$boot" > "$lock/boot"; then
    rm -f "$lock/pid" "$lock/boot"
    rmdir "$lock" 2> /dev/null || true
    return 1
  fi
  CLUSTER_LIFECYCLE_LOCK_PATH="$lock"
  CLUSTER_LIFECYCLE_LOCK_PID="$BASHPID"
}

cluster_lifecycle_lock_acquire() {
  local lock="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_PEER_STATE_FILE")}/cluster-lifecycle.lock"
  local owner="" boot="" boot_raw="" current_boot="" reason="" had_pid=false mtime="" now="" age=""
  local stat_bin="${CLUSTER_STAT_BIN:-/usr/bin/stat}" claim="$lock/reclaim"
  if mkdir "$lock" 2> /dev/null; then
    cluster_lifecycle_lock_record "$lock" && return 0
    return 1
  fi
  [ -d "$lock" ] || return 1
  current_boot="$(current_boot_epoch)"
  case "$current_boot" in '' | *[!0-9]*) current_boot=0 ;; esac
  boot_raw="$(cat "$lock/boot" 2> /dev/null || true)"
  boot="$boot_raw"
  case "$boot" in '' | *[!0-9]*) boot="" ;; esac
  if [ -n "$boot" ] && [ "$boot" != 0 ] && [ "$current_boot" != 0 ] && [ "$boot" != "$current_boot" ]; then
    reason=other-boot
  fi
  if [ -f "$lock/pid" ]; then
    had_pid=true
    owner="$(cat "$lock/pid" 2> /dev/null || true)"
    if [ "$reason" != other-boot ]; then
      case "$owner" in '' | *[!0-9]*) return 1 ;; esac
      kill -0 "$owner" 2> /dev/null && return 1
      reason=dead-pid
    fi
  elif [ -z "$reason" ]; then
    mtime="$("$stat_bin" -f %m "$lock" 2> /dev/null || true)"
    case "$mtime" in '' | *[!0-9]*) mtime="$("$stat_bin" -c %Y "$lock" 2> /dev/null || true)" ;; esac
    now="$(date +%s)"
    case "$mtime:$now" in *[!0-9:]* | :* | *:) return 1 ;; esac
    age=$((now - mtime))
    [ "$age" -gt 60 ] || return 1
    reason=ownerless
  fi
  mkdir "$claim" 2> /dev/null || return 1
  if [ -f "$lock/pid" ]; then
    [ "$had_pid" = true ] || { rmdir "$claim" 2> /dev/null || true; return 1; }
    [ "$(cat "$lock/pid" 2> /dev/null || true)" = "$owner" ] || {
      rmdir "$claim" 2> /dev/null || true
      return 1
    }
  elif [ "$had_pid" = true ]; then
    rmdir "$claim" 2> /dev/null || true
    return 1
  fi
  [ "$(cat "$lock/boot" 2> /dev/null || true)" = "$boot_raw" ] || {
    rmdir "$claim" 2> /dev/null || true
    return 1
  }
  case "$reason" in
    dead-pid) kill -0 "$owner" 2> /dev/null && { rmdir "$claim" 2> /dev/null || true; return 1; } ;;
    other-boot) [ "$boot" != "$current_boot" ] || { rmdir "$claim" 2> /dev/null || true; return 1; } ;;
    ownerless) [ ! -f "$lock/pid" ] || { rmdir "$claim" 2> /dev/null || true; return 1; } ;;
  esac
  rm -f "$lock/pid" "$lock/boot" || { rmdir "$claim" 2> /dev/null || true; return 1; }
  rmdir "$claim" 2> /dev/null || return 1
  rmdir "$lock" 2> /dev/null || return 1
  echo "cluster-lifecycle: lifecycle-lock reclaimed reason=$reason"
  if mkdir "$lock" 2> /dev/null; then
    cluster_lifecycle_lock_record "$lock" && return 0
  fi
  return 1
}

cluster_lifecycle_lock_release() {
  local owner
  [ -n "${CLUSTER_LIFECYCLE_LOCK_PATH:-}" ] || return 0
  owner="$(cat "$CLUSTER_LIFECYCLE_LOCK_PATH/pid" 2> /dev/null || true)"
  if [ "$owner" = "${CLUSTER_LIFECYCLE_LOCK_PID:-}" ]; then
    rm -f "$CLUSTER_LIFECYCLE_LOCK_PATH/pid" "$CLUSTER_LIFECYCLE_LOCK_PATH/boot"
    rmdir "$CLUSTER_LIFECYCLE_LOCK_PATH" 2> /dev/null || true
  fi
  CLUSTER_LIFECYCLE_LOCK_PATH=""
  CLUSTER_LIFECYCLE_LOCK_PID=""
}

cluster_restore_quiesced_agents() {
  local uid line label path plist rc agents_file="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_PEER_STATE_FILE")}/quiesced-agents"
  [ -f "$agents_file" ] || return 0
  uid="$(id -u)"
  # Each line is a label, optionally followed by the plist path launchd reported at quiesce time.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    label="${line%% *}"
    path=""
    [ "$line" = "$label" ] || path="${line#* }"
    plist="${path:-${CLUSTER_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/$label.plist}"
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
