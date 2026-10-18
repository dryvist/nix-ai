# shellcheck shell=bash
# cluster-join -- guarded, one-shot cluster bring-up.

join_fail() {
  lifecycle_refuse usage "$*"
  exit 1
}

join_refuse() {
  lifecycle_refuse "$1" "$2"
}

cluster_model_refuse() {
  local detail="$1"
  lifecycle_refuse model-not-cached "$detail"
  return 1
}

cluster_model_file_size() {
  local file="$1" size stat_bin="${CLUSTER_MODEL_STAT_BIN:-stat}"
  if size="$("$stat_bin" -L -f %z "$file" 2> /dev/null)" && [[ "$size" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$size"
    return 0
  fi
  if size="$("$stat_bin" -L -c %s "$file" 2> /dev/null)" && [[ "$size" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$size"
    return 0
  fi
  return 1
}

cluster_join_model_select() {
  local model="$1" explicit="$2" pipeline_requested="$3"
  local org repo cache_dir ref revision snapshot_dir file size total_bytes=0 total_mb shard_mb ceiling reserve limit found_safetensors=false
  local LC_ALL=C
  if ! [[ "$model" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    cluster_model_refuse invalid-model-id
    return 1
  fi
  org="${model%%/*}"
  repo="${model#*/}"
  cache_dir="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--$org--$repo"
  ref="$cache_dir/refs/main"
  if [ ! -f "$ref" ]; then
    cluster_model_refuse "$ref"
    return 1
  fi
  revision="$(cat "$ref")"
  if ! [[ "$revision" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    cluster_model_refuse "$ref"
    return 1
  fi
  snapshot_dir="$cache_dir/snapshots/$revision"
  if [ ! -d "$snapshot_dir" ] || [ ! -f "$snapshot_dir/config.json" ]; then
    cluster_model_refuse "$snapshot_dir"
    return 1
  fi
  JOIN_MODEL_ID="$model"
  JOIN_MODEL_REVISION="$revision"
  if [ "$explicit" = true ]; then
    JOIN_SHARDING=tensor
  else
    case "${CLUSTER_SHARDING_MODE:-tensor}" in
      tensor | tensor-parallel) JOIN_SHARDING=tensor ;;
      pipeline) JOIN_SHARDING=pipeline ;;
      *)
        cluster_model_refuse 'invalid configured sharding mode'
        return 1
        ;;
    esac
  fi
  [ "$pipeline_requested" = false ] || JOIN_SHARDING=pipeline
  JOIN_SHARD_MEMORY_MB="${CLUSTER_SHARD_MEMORY_MB:-0}"
  JOIN_MODEL_EXPLICIT="$explicit"
  JOIN_PIPELINE_EXPLICIT="$pipeline_requested"
  for file in "$snapshot_dir"/*.safetensors; do
    [ -f "$file" ] || continue
    found_safetensors=true
    if [ "$explicit" = true ]; then
      if ! size="$(cluster_model_file_size "$file")" || ! [[ "$size" =~ ^[0-9]{1,16}$ ]]; then
        cluster_model_refuse "$file"
        return 1
      fi
      size=$((10#$size))
      if [ "$size" -gt 9007199254740991 ] || [ "$total_bytes" -gt $((9007199254740991 - size)) ]; then
        lifecycle_refuse model-too-large "snapshot size exceeds safe measurement range"
        return 1
      fi
      total_bytes=$((total_bytes + size))
    fi
  done
  [ "$found_safetensors" = true ] || {
    cluster_model_refuse "$snapshot_dir"
    return 1
  }
  if [ "$explicit" = true ]; then
    if [ "$total_bytes" -le 0 ]; then
      cluster_model_refuse "$snapshot_dir"
      return 1
    fi
    total_mb=$(((total_bytes + 1048575) / 1048576))
    shard_mb=$(((total_mb * 11 + 19) / 20))
    JOIN_SHARD_MEMORY_MB="$shard_mb"
    ceiling="${CLUSTER_WIRED_LIMIT_MB:-}"
    reserve="${CLUSTER_COMPOSITOR_RESERVE_MB:-}"
    if ! [[ "$ceiling" =~ ^[0-9]{1,8}$ ]] || ! [[ "$reserve" =~ ^[0-9]{1,8}$ ]]; then
      lifecycle_refuse model-too-large "local wired ceiling is unconfigured"
      return 1
    fi
    limit=$((10#$ceiling - 10#$reserve))
    if [ "$shard_mb" -gt "$limit" ]; then
      lifecycle_refuse model-too-large "shard_mb=$shard_mb ceiling_mb=$limit"
      return 1
    fi
    printf 'cluster-join: model id=%s rev=%s total_mb=%s shard_mb=%s sharding=%s\n' \
      "$JOIN_MODEL_ID" "$JOIN_MODEL_REVISION" "$total_mb" "$shard_mb" "$JOIN_SHARDING"
  fi
  return 0
}

cluster_rank_model_write() {
  local dir="${CLUSTER_STATE_DIR:-$state_dir}" file tmp
  case "${JOIN_SHARDING:-}" in tensor | pipeline) ;; *) return 1 ;; esac
  [[ "${JOIN_MODEL_ID:-}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  mkdir -p "$dir" || return 1
  file="$dir/rank-model"
  tmp="$file.tmp.$$"
  if ! printf '%s\n%s\n' "$JOIN_MODEL_ID" "$JOIN_SHARDING" > "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
}

cluster_peer_ssh_start() {
  [ "${CLUSTER_ROLE:-}" = coordinator ] || return 0
  [ -n "${CLUSTER_PEER_SSH:-}" ] || return 0
  local -a join_args=(cluster-join --worker --session "$JOIN_SESSION_ID")
  if [ "${JOIN_MODEL_EXPLICIT:-false}" = true ]; then
    join_args+=(--model "$JOIN_MODEL_ID")
  fi
  if [ "${JOIN_PIPELINE_EXPLICIT:-false}" = true ]; then
    join_args+=(--pipeline)
  fi
  "${CLUSTER_SSH_BIN:-/usr/bin/ssh}" -o BatchMode=yes -o ConnectTimeout=10 \
    "$CLUSTER_PEER_SSH" "${join_args[@]}" \
    > >(while IFS= read -r line || [ -n "$line" ]; do printf 'worker: %s\n' "$line"; done) 2>&1 &
  CLUSTER_PEER_SSH_PID=$!
  echo "cluster-join: peer-ssh started pid=$CLUSTER_PEER_SSH_PID"
}

cluster_quiesce_wait() {
  local label="$1" deadline
  deadline=$(($(date +%s) + ${CLUSTER_QUIESCE_GRACE_SECS:-30}))
  while "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" print "gui/$uid/$label" > /dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "cluster-join: quiesce wait timed out for $label" >&2
      return 0
    fi
    sleep 1
  done
  return 0
}

cluster_quiesce_record() {
  local label="$1" file="${CLUSTER_STATE_DIR:-$state_dir}/quiesced-agents"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  "${CLUSTER_GREP_BIN:-/usr/bin/grep}" -Fqx "$label" "$file" || printf '%s\n' "$label" >> "$file"
}

cluster_quiesce_launchd_label() {
  local kind="$1" label="$2" rc=0
  if [ "$kind" = launchd ]; then
    if ! cluster_quiesce_record "$label"; then
      echo "cluster-join: quiesce record $label rc=1" >&2
    fi
  fi
  "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" bootout "gui/$uid/$label" > /dev/null 2>&1 || rc=$?
  echo "cluster-join: quiesce $kind $label rc=$rc"
  cluster_quiesce_wait "$label" || true
}

cluster_application_labels() {
  local bundle="$1" prefix listing rc=0 label suffix count first second
  local -a parts=()
  prefix="application.$bundle."
  listing="$("${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" list 2> /dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "cluster-join: quiesce app-discovery $bundle rc=$rc" >&2
    return 0
  fi
  while read -r label; do
    [ -n "$label" ] || continue
    case "$label" in "$prefix"*)
      suffix="${label#"$prefix"}"
      IFS='.' read -r -a parts <<< "$suffix"
      count="${#parts[@]}"
      [ "$count" -eq 2 ] || continue
      first="${parts[0]}"
      second="${parts[1]}"
      case "$first" in '' | *[!0-9]*) continue ;; esac
      case "$second" in '' | *[!0-9]*) continue ;; esac
      printf '%s\n' "$label"
      ;;
    esac
  done < <(printf '%s\n' "$listing" | "${CLUSTER_AWK_BIN:-/usr/bin/awk}" -v prefix="$prefix" "index(\$3, prefix) == 1 {print \$3}")
}

cluster_quiesce_apps() {
  local bundle label
  local -a bundles=()
  IFS=' ' read -r -a bundles <<< "${CLUSTER_QUIESCE_APPS:-}"
  for bundle in "${bundles[@]}"; do
    [ -n "$bundle" ] || continue
    while IFS= read -r label; do
      [ -n "$label" ] || continue
      cluster_quiesce_launchd_label app "$label"
    done < <(cluster_application_labels "$bundle")
  done
}

cluster_quiesce_configured_launchd() {
  local label
  local -a labels=()
  IFS=' ' read -r -a labels <<< "${CLUSTER_QUIESCE_LAUNCHD:-}"
  for label in "${labels[@]}"; do
    [ -n "$label" ] || continue
    cluster_quiesce_launchd_label launchd "$label"
  done
}

cluster_quiesce_coordinator_serving() {
  local label grace deadline
  local -a labels=()
  curl -fsS -m 30 -X POST "${CLUSTER_NORMAL_PROXY:-}/api/models/unload" > /dev/null 2>&1 || true
  IFS=' ' read -r -a labels <<< "${CLUSTER_SERVER_LABELS:-}"
  for label in "${labels[@]}"; do
    [ -n "$label" ] || continue
    local rc=0
    "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" bootout "gui/$uid/$label" > /dev/null 2>&1 || rc=$?
    echo "cluster-join: quiesce serving $label rc=$rc"
  done
  if [ -n "${CLUSTER_WATCHDOG_LABEL:-}" ]; then
    local rc=0
    "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" bootout "gui/$uid/$CLUSTER_WATCHDOG_LABEL" > /dev/null 2>&1 || rc=$?
    echo "cluster-join: quiesce watchdog $CLUSTER_WATCHDOG_LABEL rc=$rc"
  fi
  standalone_serve_pids() {
    local pid cmd pat exempt
    "${CLUSTER_PGREP_BIN:-/usr/bin/pgrep}" -f "${CLUSTER_STANDALONE_PROCESS_PATTERN:-vllm-mlx serve}" 2> /dev/null |
      while read -r pid; do
        cmd="$("${CLUSTER_PS_BIN:-/bin/ps}" -ww -p "$pid" -o command= 2> /dev/null)"
        exempt=false
        if [ -n "${CLUSTER_KEEP_RESIDENT:-}" ]; then
          while IFS= read -r pat; do
            [ -n "$pat" ] || continue
            case "$cmd" in *"$pat"*) exempt=true; break ;; esac
          done <<< "$CLUSTER_KEEP_RESIDENT"
        fi
        [ "$exempt" = true ] || printf '%s\n' "$pid"
      done
  }
  grace="${CLUSTER_QUIESCE_GRACE_SECS:-30}"
  deadline=$(($(date +%s) + grace))
  while [ -n "$(standalone_serve_pids)" ] && [ "$(date +%s)" -lt "$deadline" ]; do sleep 2; done
  if [ -n "$(standalone_serve_pids)" ]; then
    echo "cluster-join: standalone-serve engines remain after ${grace}s; requesting TERM"
    standalone_serve_pids | while read -r pid; do "${CLUSTER_KILL_BIN:-/bin/kill}" -TERM "$pid" > /dev/null 2>&1 || true; done
    sleep 3
  fi
  if [ -n "$(standalone_serve_pids)" ]; then
    echo "cluster-join: WARN standalone-serve engines remain after quiesce; the room check will decide whether to continue" >&2
  fi
}

cluster_join_quiesce() {
  local used threshold
  quiesced=true
  if [ "$CLUSTER_ROLE" = coordinator ]; then
    used="$("${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}" -n vm.swapusage 2> /dev/null |
      "${CLUSTER_SED_BIN:-/usr/bin/sed}" -n 's/.*used = \([0-9][0-9]*\).*/\1/p' || true)"
    used="${used:-0}"
    threshold="${CLUSTER_JOIN_SWAP_THRESHOLD_MB:-8000}"
    if [ "$used" -gt "$threshold" ]; then
      join_refuse stale-swap "${used}M used exceeds ${threshold}M; reboot this Mac before joining"
      exit 1
    fi
    echo "cluster-join: swap PASS used=${used}M threshold=${threshold}M"
    cluster_quiesce_coordinator_serving
    cluster_quiesce_apps
    cluster_quiesce_configured_launchd
  elif [ -n "${CLUSTER_QUIESCE_CMD:-}" ]; then
    "${CLUSTER_SH_BIN:-/bin/sh}" -c "$CLUSTER_QUIESCE_CMD" || echo "cluster-join: WARN worker quiesce hook failed"
  fi
}

cluster_join_exit() {
  local rc=$? teardown_rc=0 peer_rc=0 peer_started=false peer_wait_rc=0 teardown_done=false cleanup_rc=0
  JOIN_EXIT_ACTIVE=true
  trap - EXIT
  trap 'cluster_join_signal 130' INT
  trap 'cluster_join_signal 143' TERM
  if [ "${formed:-false}" != true ] && {
    [ "${ceiling_attempted:-false}" = true ] || [ "${quiesced:-false}" = true ] ||
      [ -n "${JOIN_SESSION_ID:-}" ];
  }; then
    cluster_teardown "${JOIN_SESSION_ID:-}" || teardown_rc=$?
    teardown_done=true
    if [ "${JOIN_REBOOT:-0}" -eq 1 ] || [ "${TEARDOWN_REBOOT:-0}" -eq 1 ]; then
      rc=3
    elif [ "$rc" -eq 0 ] || [ "$teardown_rc" -ne 0 ] || [ "${TEARDOWN_FAILED:-0}" -ne 0 ]; then
      rc=1
    fi
  fi
  if [ -n "${CLUSTER_PEER_SSH_PID:-}" ]; then
    peer_started=true
    cluster_peer_ssh_wait || peer_wait_rc=$?
    peer_rc="${CLUSTER_PEER_SSH_RC:-$peer_wait_rc}"
  fi
  if [ "${JOIN_SIGNAL_RC:-0}" -ne 0 ]; then
    rc=$JOIN_SIGNAL_RC
  elif [ "$peer_started" = true ] && [ "$peer_rc" -ne 0 ]; then
    lifecycle_refuse peer-join-failed "worker join failed or could not be reaped (rc=$peer_rc)"
    if [ "$teardown_done" = false ]; then
      cluster_teardown "${JOIN_SESSION_ID:-}" || teardown_rc=$?
      teardown_done=true
    fi
    if [ "$peer_rc" -eq 3 ]; then
      rc=3
    elif [ "$rc" -eq 0 ] || [ "$teardown_rc" -ne 0 ] || [ "${TEARDOWN_FAILED:-0}" -ne 0 ]; then
      rc=1
    fi
  fi
  if [ "$peer_started" = true ] && {
    [ "$rc" -ne 0 ] || [ "${JOIN_SIGNAL_RC:-0}" -ne 0 ] ||
      [ "${TEARDOWN_FAILED:-0}" -ne 0 ];
  }; then
    if cluster_peer_remote_detach; then
      :
    else
      cleanup_rc=$?
      if [ "${JOIN_SIGNAL_RC:-0}" -eq 0 ]; then
        if [ "$cleanup_rc" -eq 3 ]; then rc=3; elif [ "$rc" -ne 3 ]; then rc=1; fi
      fi
    fi
  fi
  [ "${JOIN_SIGNAL_RC:-0}" -eq 0 ] || rc=$JOIN_SIGNAL_RC
  trap - INT TERM
  cluster_lifecycle_lock_release
  exit "$rc"
}

cluster_peer_remote_detach() {
  local cleanup_pid
  [ "${CLUSTER_ROLE:-}" = coordinator ] || return 0
  [ -n "${CLUSTER_PEER_SSH:-}" ] &&
    [[ "${JOIN_SESSION_ID:-}" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || {
    lifecycle_refuse peer-cleanup-unconfirmed "worker session is unavailable for remote cleanup"
    return 1
  }
  echo "cluster-join: peer-ssh requesting session-scoped worker detach"
  "${CLUSTER_SSH_BIN:-/usr/bin/ssh}" -o BatchMode=yes -o ConnectTimeout=10 \
    "$CLUSTER_PEER_SSH" cluster-detach --worker --session "$JOIN_SESSION_ID" \
    > >(while IFS= read -r line || [ -n "$line" ]; do printf 'worker-cleanup: %s\n' "$line"; done) 2>&1 &
  cleanup_pid=$!
  if cluster_peer_ssh_wait "$cleanup_pid" "${CLUSTER_JOIN_TIMEOUT_SECS:-600}" peer-ssh-timeout true; then
    case "${CLUSTER_PEER_SSH_RC:-1}" in
      0)
        echo "cluster-join: peer-ssh worker detach acknowledged session=$JOIN_SESSION_ID"
        return 0
        ;;
      3)
        lifecycle_refuse peer-cleanup-reboot-required \
          "worker detached session $JOIN_SESSION_ID but requires reboot before another join"
        return 3
        ;;
    esac
  fi
  lifecycle_refuse peer-cleanup-unconfirmed \
    "remote detach for session $JOIN_SESSION_ID failed or could not be confirmed (rc=${CLUSTER_PEER_SSH_RC:-unknown})"
  return 1
}

cluster_join_signal() {
  local signal_rc="$1"
  if [ "${JOIN_EXIT_ACTIVE:-false}" = true ]; then
    JOIN_SIGNAL_RC="$signal_rc"
  else
    exit "$signal_rc"
  fi
}

cluster_sleep_until() {
  local target="$1" deadline="${2:-$((SECONDS + ${CLUSTER_JOIN_TIMEOUT_SECS:-600}))}" now remaining monotonic_left
  while :; do
    now="$(date +%s)"
    case "$now" in '' | *[!0-9]*) return 1 ;; esac
    [ "$now" -lt "$target" ] || break
    monotonic_left=$((deadline - SECONDS))
    [ "$monotonic_left" -gt 0 ] || return 1
    remaining=$((target - now))
    [ "$remaining" -le "$monotonic_left" ] || remaining="$monotonic_left"
    sleep "$remaining"
  done
  [ "$SECONDS" -le "$deadline" ]
}

cluster_join_new_session() {
  local stamp random
  stamp="$(date -u +%Y%m%dT%H%M%SZ)" || return 1
  random="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')" || return 1
  [[ "$stamp" =~ ^[0-9]{8}T[0-9]{6}Z$ && "$random" =~ ^[0-9a-f]{8}$ ]] || return 1
  printf '%s-%s\n' "$stamp" "$random"
}

cluster_join_publish_preparing() {
  if ! peer_state_write false 0 "$JOIN_SESSION_ID" preparing; then
    lifecycle_refuse preparing-state-write-failed "could not publish the current session before the worker launch"
    return 1
  fi
  if ! link_state_write down; then
    lifecycle_refuse link-state-write-failed "could not keep link-state down while preparing session $JOIN_SESSION_ID"
    return 1
  fi
}

cluster_join_final_gates() {
  echo "cluster-join: J9 final local gates"
  if ! pd_start_gate; then
    lifecycle_refuse "${PD_GATE_REASON:-pd-gate-refused}" "${PD_COUNT_DETAIL:-${PD_BUDGET_DETAIL:-protection-domain gate refused}}"
    return 1
  fi
  if ! set_wired_limit "${CLUSTER_WIRED_LIMIT_MB:-}"; then
    lifecycle_refuse wired-ceiling-set-failed "could not verify the configured cluster wired ceiling"
    return 1
  fi
  if ! rank_start_room_ok; then
    local reason=rank-start-room-unavailable
    case "${MEM_HEADROOM_DETAIL:-}" in room-unconfigured*) reason=room-unconfigured ;; esac
    lifecycle_refuse "$reason" "${MEM_HEADROOM_DETAIL:-unknown}"
    case "${MEM_HEADROOM_DETAIL:-}" in *unreclaimed-Metal*) JOIN_REBOOT=1 ;; esac
    return 1
  fi
  if ! peer_state_versions_validate; then
    lifecycle_refuse "${PEER_GATE_REASON%% *}" "$PEER_GATE_REASON"
    return 1
  fi
}

cluster_join_publish_ready() {
  JOIN_READY_AT="$(date +%s)"
  case "$JOIN_READY_AT" in '' | *[!0-9]*)
    lifecycle_refuse clock-unavailable "could not timestamp local READY state"
    return 1
    ;;
  esac
  if ! peer_state_write true "$JOIN_READY_AT" "$JOIN_SESSION_ID" ready; then
    lifecycle_refuse "${PEER_GATE_REASON%% *}" "${PEER_GATE_REASON:-could not publish local READY state}"
    return 1
  fi
  if ! link_state_write up; then
    lifecycle_refuse link-state-write-failed "could not write link-state up for READY session $JOIN_SESSION_ID"
    return 1
  fi
  echo "cluster-join: phase=ready session=$JOIN_SESSION_ID armed_at=$JOIN_READY_AT"
}

cluster_join_wait_worker_ready() {
  local timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}" deadline remaining
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if peer_armed_read; then
      echo "cluster-join: peer phase=ready session=$JOIN_SESSION_ID"
      return 0
    fi
    # A session mismatch here means the worker has not published this session yet; keep waiting.
    case "${PEER_GATE_REASON:-}" in
      version-unknown* | version-mismatch* | peer-arm-stale* | peer-arm-future* | peer-not-armed)
        lifecycle_refuse "${PEER_GATE_REASON%% *}" "$PEER_GATE_REASON"
        return 1
        ;;
      'peer-not-ready phase=abort')
        lifecycle_refuse peer-aborted "worker published abort for session $JOIN_SESSION_ID"
        return 1
        ;;
    esac
    if [ -n "${CLUSTER_PEER_SSH_PID:-}" ] && ! cluster_peer_ssh_running; then
      lifecycle_refuse peer-join-exited "worker join exited before publishing READY for session $JOIN_SESSION_ID"
      return 1
    fi
    echo "cluster-join: peer phase WAIT reason=${PEER_GATE_REASON:-unknown}"
    remaining=$((deadline - SECONDS))
    [ "$remaining" -le 5 ] || remaining=5
    sleep "$remaining"
  done
  lifecycle_refuse peer-ready-timeout "worker did not publish READY within ${timeout}s"
  return 1
}

cluster_join_publish_commit() {
  local now
  now="$(date +%s)"
  case "$now" in '' | *[!0-9]*)
    lifecycle_refuse clock-unavailable "could not timestamp the session commit"
    return 1
    ;;
  esac
  JOIN_START_AT=$((now + 20))
  if ! peer_state_write true "$JOIN_READY_AT" "$JOIN_SESSION_ID" commit "$JOIN_START_AT"; then
    lifecycle_refuse commit-state-write-failed "could not publish COMMIT for session $JOIN_SESSION_ID"
    return 1
  fi
  echo "cluster-join: phase=commit session=$JOIN_SESSION_ID start_at=$JOIN_START_AT"
}

cluster_join_peer_gate_refuse() {
  local reason="${PEER_GATE_REASON:-}"
  case "$reason" in
    peer-session-mismatch* | version-unknown* | version-mismatch*)
      lifecycle_refuse "${reason%% *}" "$reason"
      return 0
      ;;
  esac
  return 1
}

cluster_join_wait_worker_started() {
  local start_at="$1" timeout=10 deadline remaining armed
  deadline=$((SECONDS + timeout))
  while :; do
    if peer_state_session_read; then
      case "$PEER_PHASE" in
        started)
          armed="$(jq -r '.armed // false' <<< "$PEER_STATE_RAW")"
          if [ "$armed" != true ] || [ "$PEER_START_AT" != "$start_at" ]; then
            lifecycle_refuse worker-start-invalid \
              "worker STARTED did not preserve armed=true and start_at=$start_at"
            return 1
          fi
          echo "cluster-join: peer phase=started session=$JOIN_SESSION_ID start_at=$start_at"
          return 0
          ;;
        abort)
          lifecycle_refuse worker-aborted "worker aborted session $JOIN_SESSION_ID before coordinator start"
          return 1
          ;;
      esac
    elif cluster_join_peer_gate_refuse; then
      return 1
    fi
    [ "$SECONDS" -lt "$deadline" ] || break
    remaining=$((deadline - SECONDS))
    [ "$remaining" -le 1 ] || remaining=1
    sleep "$remaining"
  done
  lifecycle_refuse worker-start-timeout "worker did not acknowledge STARTED within ${timeout}s"
  return 1
}

cluster_worker_wait_commit() {
  local timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}" deadline remaining
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if peer_state_session_read; then
      case "$PEER_PHASE" in
        commit)
          [ "$PEER_START_AT" -gt 0 ] || {
            lifecycle_refuse commit-withdrawn "coordinator COMMIT has no start_at for session $JOIN_SESSION_ID"
            return 1
          }
          JOIN_START_AT="$PEER_START_AT"
          echo "cluster-join: peer phase=commit session=$JOIN_SESSION_ID start_at=$JOIN_START_AT"
          return 0
          ;;
        abort)
          lifecycle_refuse commit-withdrawn "coordinator aborted session $JOIN_SESSION_ID before COMMIT"
          return 1
          ;;
      esac
    elif cluster_join_peer_gate_refuse; then
      return 1
    fi
    echo "cluster-join: peer COMMIT WAIT reason=${PEER_GATE_REASON:-phase=$PEER_PHASE}"
    remaining=$((deadline - SECONDS))
    [ "$remaining" -le 5 ] || remaining=5
    sleep "$remaining"
  done
  lifecycle_refuse commit-timeout "coordinator did not publish COMMIT within ${timeout}s"
  return 1
}

cluster_join_wait_coordinator_formed() {
  local timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}" deadline remaining now age
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if peer_state_session_read; then
      case "$PEER_PHASE" in
        formed)
          if [ "$PEER_START_AT" != "$JOIN_START_AT" ]; then
            lifecycle_refuse coordinator-formed-start-mismatch \
              "coordinator formed start_at=$PEER_START_AT expected=$JOIN_START_AT"
            return 1
          fi
          now="$(date +%s)"
          case "$now" in '' | *[!0-9]*)
            lifecycle_refuse clock-unavailable "could not validate coordinator formed_at"
            return 1
            ;;
          esac
          age=$((now - PEER_FORMED_AT))
          if [ "$PEER_FORMED_AT" -le 0 ] || [ "$age" -gt 15 ]; then
            lifecycle_refuse coordinator-formed-stale "formed_at=$PEER_FORMED_AT age=$age max_age=15"
            return 1
          fi
          if [ "$age" -lt -5 ]; then
            lifecycle_refuse coordinator-formed-future "formed_at=$PEER_FORMED_AT age=$age future_tolerance=5"
            return 1
          fi
          echo "cluster-join: peer phase=formed formed_at=$PEER_FORMED_AT age=$age"
          return 0
          ;;
        abort)
          lifecycle_refuse coordinator-aborted "coordinator aborted session $JOIN_SESSION_ID during formation"
          return 1
          ;;
      esac
    elif cluster_join_peer_gate_refuse; then
      return 1
    fi
    cluster_join_coordinator_lease_ok || return 1
    remaining=$((deadline - SECONDS))
    [ "$remaining" -le 5 ] || remaining=5
    sleep "$remaining"
  done
  lifecycle_refuse coordinator-formation-timeout "coordinator did not confirm formation within ${timeout}s"
  return 1
}

cluster_join_wait_coordinator_session() {
  local timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}" deadline remaining
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if peer_state_session_read; then
      case "$PEER_PHASE" in
        preparing | ready) return 0 ;;
        abort)
          lifecycle_refuse no-session "coordinator aborted session $JOIN_SESSION_ID before worker READY"
          return 1
          ;;
      esac
    elif cluster_join_peer_gate_refuse; then
      return 1
    fi
    remaining=$((deadline - SECONDS))
    [ "$remaining" -le 5 ] || remaining=5
    sleep "$remaining"
  done
  lifecycle_refuse peer-session-timeout "coordinator did not publish session $JOIN_SESSION_ID within ${timeout}s"
  return 1
}

cluster_join_wait_coordinator_formed_local() {
  local timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}" deadline stable_since remaining
  deadline=$((SECONDS + timeout))
  stable_since="$SECONDS"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if "${CLUSTER_CURL_BIN:-/usr/bin/curl}" -fsS -m 5 \
      "http://127.0.0.1:${CLUSTER_HTTP_PORT}/v1/models" > /dev/null 2>&1 && rank_process_running; then
      return 0
    fi
    # Refresh the lease the worker requires while both ranks load.
    if ! peer_state_write true "$JOIN_READY_AT" "$JOIN_SESSION_ID" started "$JOIN_START_AT"; then
      lifecycle_refuse started-state-write-failed "could not refresh coordinator STARTED for session $JOIN_SESSION_ID"
      return 1
    fi
    if ! rank_process_running && [ "$((SECONDS - stable_since))" -ge 15 ]; then
      lifecycle_refuse rank-exited-during-formation "coordinator rank exited before the endpoint formed"
      return 1
    fi
    remaining=$((deadline - SECONDS))
    [ "$remaining" -le 5 ] || remaining=5
    sleep "$remaining"
  done
  lifecycle_refuse coordinator-endpoint-not-formed "endpoint and live coordinator rank did not form within ${timeout}s"
  return 1
}

cluster_join_publish_formed() {
  if [ "$CLUSTER_ROLE" = coordinator ] &&
    ! "${CLUSTER_CURL_BIN:-/usr/bin/curl}" -fsS -m 5 \
      "http://127.0.0.1:${CLUSTER_HTTP_PORT}/v1/models" > /dev/null 2>&1; then
    lifecycle_refuse coordinator-endpoint-not-formed "endpoint is not healthy before phase formed"
    return 1
  fi
  if ! rank_process_running; then
    lifecycle_refuse rank-not-running-at-formation "rank process is not live before phase formed"
    return 1
  fi
  if ! peer_state_write true "$JOIN_READY_AT" "$JOIN_SESSION_ID" formed "$JOIN_START_AT"; then
    lifecycle_refuse formed-state-write-failed "could not publish formation for session $JOIN_SESSION_ID"
    return 1
  fi
  if ! rank_process_running; then
    lifecycle_refuse rank-not-running-at-formation "rank process exited immediately before decision=formed"
    return 1
  fi
}

cluster_join_maintain_formed() {
  local timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}" deadline remaining
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! "${CLUSTER_CURL_BIN:-/usr/bin/curl}" -fsS -m 5 \
      "http://127.0.0.1:${CLUSTER_HTTP_PORT}/v1/models" > /dev/null 2>&1 || ! rank_process_running; then
      lifecycle_refuse coordinator-formation-lost "endpoint or rank became unhealthy while awaiting worker formation"
      return 1
    fi
    if ! cluster_join_publish_formed; then
      return 1
    fi
    if peer_state_session_read; then
      case "$PEER_PHASE" in
        formed)
          if [ "$PEER_START_AT" != "$JOIN_START_AT" ]; then
            lifecycle_refuse worker-formed-start-mismatch \
              "worker formed start_at=$PEER_START_AT expected=$JOIN_START_AT"
            return 1
          fi
          echo "cluster-join: peer phase=formed session=$JOIN_SESSION_ID"
          return 0
          ;;
        abort)
          lifecycle_refuse worker-aborted "worker aborted session $JOIN_SESSION_ID during formation"
          return 1
          ;;
      esac
    elif cluster_join_peer_gate_refuse; then
      return 1
    fi
    remaining=$((deadline - SECONDS))
    [ "$remaining" -le 5 ] || remaining=5
    sleep "$remaining"
  done
  lifecycle_refuse worker-formation-timeout "worker did not confirm formation within ${timeout}s"
  return 1
}

cluster_final_rank_start() {
  local start_at="$1" now local_phase local_session local_start_at deadline process_deadline uid
  cluster_rank_model_write || {
    lifecycle_refuse rank-model-write-failed "could not persist the selected rank model"
    return 1
  }
  deadline=$((SECONDS + ${CLUSTER_JOIN_TIMEOUT_SECS:-600}))
  cluster_sleep_until "$start_at" "$deadline" || {
    lifecycle_refuse missed-start-window "start_at=$start_at was missed or exceeded the join timeout"
    return 1
  }
  # JACCL has an approximately 15s connect budget, so cap worker acknowledgement at 10s.
  if [ "$CLUSTER_ROLE" = coordinator ] && ! cluster_join_wait_worker_started "$start_at"; then
    return 1
  fi
  while :; do
    local_session="$(jq -r '.session // ""' "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || true)"
    local_phase="$(jq -r '.phase // ""' "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || true)"
    local_start_at="$(jq -r '.start_at // 0' "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || true)"
    if [ "$local_session" != "$JOIN_SESSION_ID" ]; then
      lifecycle_refuse local-session-withdrawn "local state no longer names session $JOIN_SESSION_ID"
      return 1
    fi
    if [ "$CLUSTER_ROLE" = worker ] && [ "$local_phase" != ready ]; then
      lifecycle_refuse commit-withdrawn "local READY state was withdrawn before kickstart"
      return 1
    fi
    if [ "$CLUSTER_ROLE" = coordinator ]; then
      if [ "$local_phase" != commit ] || [ "$local_start_at" != "$start_at" ]; then
        lifecycle_refuse commit-withdrawn "local COMMIT for session $JOIN_SESSION_ID was withdrawn or changed before kickstart"
        return 1
      fi
      if ! peer_state_session_read || [ "$PEER_PHASE" != started ] || [ "$PEER_START_AT" != "$start_at" ]; then
        lifecycle_refuse worker-start-withdrawn "worker STARTED for session $JOIN_SESSION_ID was withdrawn before coordinator kickstart"
        return 1
      fi
    else
      if ! peer_state_session_read; then
        if cluster_join_peer_gate_refuse; then return 1; fi
        lifecycle_refuse commit-withdrawn \
          "coordinator COMMIT for session $JOIN_SESSION_ID was withdrawn before kickstart"
        return 1
      fi
      if [ "$PEER_PHASE" != commit ] || [ "$PEER_START_AT" != "$start_at" ]; then
        lifecycle_refuse commit-withdrawn "coordinator COMMIT for session $JOIN_SESSION_ID was withdrawn or changed before kickstart"
        return 1
      fi
    fi
    now="$(date +%s)"
    case "$now" in '' | *[!0-9]*)
      lifecycle_refuse clock-unavailable "could not validate aligned start time"
      return 1
      ;;
    esac
    if [ "$now" -lt "$start_at" ]; then
      cluster_sleep_until "$start_at" "$deadline" || {
        lifecycle_refuse missed-start-window "start_at=$start_at was missed or exceeded the join timeout"
        return 1
      }
      continue
    fi
    if [ "$CLUSTER_ROLE" = worker ] && [ "$now" -gt "$((start_at + 2))" ]; then
      lifecycle_refuse missed-start-window "worker accepted COMMIT at $now after start_at=$start_at tolerance=2"
      return 1
    fi
    # Worker starts by start_at+2; starting by start_at+10 keeps the gap inside JACCL's ~15s connect budget.
    if [ "$CLUSTER_ROLE" = coordinator ] && [ "$now" -gt "$((start_at + 10))" ]; then
      lifecycle_refuse missed-start-window "coordinator reached kickstart at $now after start_at=$start_at tolerance=10"
      return 1
    fi
    break
  done
  uid="$(id -u)"
  "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" kickstart "gui/$uid/${CLUSTER_RANK_LABEL}" || {
    lifecycle_refuse rank-kickstart-failed "launchctl kickstart failed for the configured rank label"
    return 1
  }
  echo "cluster-join: kickstart issued at $now"
  if [ "$CLUSTER_ROLE" = worker ]; then
    process_deadline=$((SECONDS + 5))
    while [ "$SECONDS" -lt "$process_deadline" ] && ! rank_process_running; do sleep 1; done
    if ! rank_process_running; then
      lifecycle_refuse worker-rank-not-running "worker rank did not run within 5s of kickstart"
      return 1
    fi
  fi
  if ! peer_state_write true "$JOIN_READY_AT" "$JOIN_SESSION_ID" started "$start_at"; then
    lifecycle_refuse started-state-write-failed "could not publish $CLUSTER_ROLE STARTED for session $JOIN_SESSION_ID"
    return 1
  fi
  echo "cluster-join: phase=started session=$JOIN_SESSION_ID start_at=$start_at"
  COORDINATOR_LEASE_TS=""
  COORDINATOR_LEASE_SEEN="$SECONDS"
}

# Worker only: stop the rank when the coordinator aborts, changes session, or stops refreshing its state.
cluster_join_coordinator_lease_ok() {
  local lease="${CLUSTER_COORDINATOR_LEASE_SECS:-30}"
  if peer_state_session_read; then
    if [ "$PEER_PHASE" = abort ]; then
      lifecycle_refuse coordinator-aborted "coordinator aborted session $JOIN_SESSION_ID after worker start"
      return 1
    fi
    if [ "$PEER_TS" != "${COORDINATOR_LEASE_TS:-}" ]; then
      COORDINATOR_LEASE_TS="$PEER_TS"
      COORDINATOR_LEASE_SEEN="$SECONDS"
    fi
  elif cluster_join_peer_gate_refuse; then
    return 1
  fi
  if [ "$((SECONDS - ${COORDINATOR_LEASE_SEEN:-0}))" -gt "$lease" ]; then
    lifecycle_refuse coordinator-lease-expired "coordinator state for session $JOIN_SESSION_ID not refreshed for over ${lease}s"
    return 1
  fi
}

cluster_join_main() {
  local timeout deadline now session_arg=""
  local launchctl_bin="${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}"
  local rank_pid warm_ok=false stable_since=0 stable_required worker_invocation=false
  local model_explicit=false pipeline_requested=false model_arg="" selected_model
  local held="?"
  state_dir="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_STATE_FILE")}"
  mkdir -p "$state_dir"
  export CLUSTER_LIFECYCLE_COMPONENT=cluster-join
  cluster_lifecycle_log_start
  formed=false
  quiesced=false
  ceiling_attempted=false
  JOIN_REBOOT=0
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  JOIN_SESSION_ID=""
  JOIN_READY_AT=0
  JOIN_START_AT=0
  CLUSTER_PEER_SSH_PID=""
  CLUSTER_PEER_SSH_RC=0
  TEARDOWN_FAILED=0
  TEARDOWN_REBOOT=0
  trap cluster_join_exit EXIT
  trap 'cluster_join_signal 130' INT
  trap 'cluster_join_signal 143' TERM
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worker)
        [ "$worker_invocation" = false ] || join_fail "cluster-join [--worker --session ID] [--model org/repo] [--pipeline]"
        worker_invocation=true
        shift
        ;;
      --session)
        [ -z "$session_arg" ] && [ "$#" -ge 2 ] || join_fail "cluster-join [--worker --session ID] [--model org/repo] [--pipeline]"
        session_arg="$2"
        shift 2
        ;;
      --model)
        [ "$model_explicit" = false ] && [ "$#" -ge 2 ] || join_fail "cluster-join [--worker --session ID] [--model org/repo] [--pipeline]"
        model_arg="$2"
        model_explicit=true
        shift 2
        ;;
      --pipeline)
        [ "$pipeline_requested" = false ] || join_fail "cluster-join [--worker --session ID] [--model org/repo] [--pipeline]"
        pipeline_requested=true
        shift
        ;;
      *) join_fail "cluster-join [--worker --session ID] [--model org/repo] [--pipeline]" ;;
    esac
  done
  [ "$pipeline_requested" = false ] || [ "$model_explicit" = true ] ||
    join_fail "--pipeline requires --model"
  if [ "$worker_invocation" = true ]; then
    [[ "$session_arg" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || {
      lifecycle_refuse no-session "worker invocation requires --session with the coordinator's join id"
      exit 1
    }
    [ "${CLUSTER_ROLE:-}" = worker ] || join_fail "--worker is only valid on the worker role"
    JOIN_SESSION_ID="$session_arg"
  elif [ -n "$session_arg" ]; then
    join_fail "--session is only valid with --worker"
  fi
  if ! cluster_lifecycle_lock_acquire; then
    lifecycle_refuse lifecycle-locked "another cluster lifecycle transaction owns $state_dir"
    exit 1
  fi
  uid="$(id -u)"
  [ "$worker_invocation" = false ] || echo "cluster-join: peer worker invocation accepted"

  selected_model="${CLUSTER_MODEL:-}"
  [ "$model_explicit" = false ] || selected_model="$model_arg"
  if ! cluster_join_model_select "$selected_model" "$model_explicit" "$pipeline_requested"; then
    exit 1
  fi

  echo "cluster-join: J1 pd-start-gate"
  if pd_start_gate; then
    :
  else
    lifecycle_refuse "${PD_GATE_REASON:-pd-gate-refused}" "${PD_COUNT_DETAIL:-${PD_BUDGET_DETAIL:-protection-domain gate refused}}"
    if [ "${PD_REBOOT:-0}" = 1 ]; then
      JOIN_REBOOT=1
      exit 3
    fi
    exit 1
  fi

  echo "cluster-join: J2 link-prep check"
  if link_prep_ok; then
    echo "cluster-join: link-prep PASS"
  else
    join_refuse link-prep-not-ready "run sudo /nix/var/nix/profiles/system/activate"
    exit 1
  fi

  echo "cluster-join: J3 wired-ceiling"
  ceiling_attempted=true
  if set_wired_limit "${CLUSTER_WIRED_LIMIT_MB:-}"; then
    echo "cluster-join: wired-ceiling PASS"
  else
    join_refuse wired-ceiling-set-failed "could not set the configured cluster wired ceiling"
    exit 1
  fi

  echo "cluster-join: J4 quiesce"
  cluster_join_quiesce

  echo "cluster-join: J5 room check"
  if [ "$JOIN_MODEL_EXPLICIT" = true ]; then
    CLUSTER_SHARD_MEMORY_MB="$JOIN_SHARD_MEMORY_MB"
  fi
  if rank_start_room_ok; then
    echo "cluster-join: room PASS"
  else
    local reason=rank-start-room-unavailable
    case "${MEM_HEADROOM_DETAIL:-}" in room-unconfigured*) reason=room-unconfigured ;; esac
    lifecycle_refuse "$reason" "${MEM_HEADROOM_DETAIL:-unknown}"
    case "${MEM_HEADROOM_DETAIL:-}" in *unreclaimed-Metal*) JOIN_REBOOT=1 ;; esac
    exit "$((JOIN_REBOOT == 1 ? 3 : 1))"
  fi

  echo "cluster-join: J6 prepare session"
  if [ "$worker_invocation" = false ]; then
    if ! JOIN_SESSION_ID="$(cluster_join_new_session)"; then
      lifecycle_refuse no-session "could not mint a session id"
      exit 1
    fi
  fi
  if ! cluster_join_publish_preparing; then
    exit 1
  fi
  if [ "$worker_invocation" = false ]; then
    cluster_peer_ssh_start || {
      lifecycle_refuse peer-ssh-start-failed "could not start the worker join command"
      exit 1
    }
  else
    echo "cluster-join: session accepted id=$JOIN_SESSION_ID"
    if ! cluster_join_wait_coordinator_session; then
      exit 1
    fi
  fi

  if ! cluster_join_final_gates || ! cluster_join_publish_ready; then
    [ "${PD_REBOOT:-0}" -eq 1 ] && JOIN_REBOOT=1
    exit "$((JOIN_REBOOT == 1 ? 3 : 1))"
  fi

  if [ "$CLUSTER_ROLE" = coordinator ]; then
    echo "cluster-join: J8 wait worker READY"
    if ! cluster_join_wait_worker_ready || ! cluster_join_publish_commit; then
      exit 1
    fi
  else
    echo "cluster-join: J8 wait coordinator COMMIT"
    if ! cluster_worker_wait_commit; then
      exit 1
    fi
  fi

  echo "cluster-join: J9 start_at=$JOIN_START_AT"
  if ! cluster_final_rank_start "$JOIN_START_AT"; then
    [ "${PD_REBOOT:-0}" -eq 1 ] && JOIN_REBOOT=1
    exit "$((JOIN_REBOOT == 1 ? 3 : 1))"
  fi

  echo "cluster-join: J10 formation check"
  timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}"
  deadline=$((SECONDS + timeout))
  if [ "$CLUSTER_ROLE" = coordinator ]; then
    if ! cluster_join_wait_coordinator_formed_local; then
      exit 1
    fi
  else
    stable_required="${CLUSTER_WORKER_STABLE_SECS:-60}"
    stable_since=0
    while [ "$SECONDS" -lt "$deadline" ]; do
      if "$launchctl_bin" print "gui/$uid/${CLUSTER_RANK_LABEL}" 2> /dev/null |
        "${CLUSTER_GREP_BIN:-/usr/bin/grep}" -q 'state = running' && rank_process_running; then
        [ "$stable_since" -gt 0 ] || stable_since="$SECONDS"
        if [ "$((SECONDS - stable_since))" -ge "$stable_required" ]; then
          warm_ok=true
          break
        fi
      else
        stable_since=0
        if [ "$((SECONDS - (deadline - timeout)))" -ge 15 ] && ! rank_process_running; then
          lifecycle_refuse worker-rank-exited-during-formation "worker rank exited during the stability window"
          exit 1
        fi
      fi
      cluster_join_coordinator_lease_ok || exit 1
      local remaining=$((deadline - SECONDS))
      [ "$remaining" -le 5 ] || remaining=5
      sleep "$remaining"
    done
    if [ "$warm_ok" != true ]; then
      lifecycle_refuse worker-rank-not-stable "rank did not stay up for ${stable_required}s"
      exit 1
    fi
    if ! cluster_join_wait_coordinator_formed; then
      exit 1
    fi
  fi

  if ! cluster_join_publish_formed; then
    exit 1
  fi
  if [ "$CLUSTER_ROLE" = coordinator ] && ! cluster_join_maintain_formed; then
    exit 1
  fi

  rank_pid="$(rank_process_pids 2> /dev/null | head -n 1 || true)"
  if pd_held_count; then held="$PD_HELD"; else held="?"; fi
  if ! rank_process_running; then
    lifecycle_refuse rank-not-running-at-formation "rank process exited immediately before decision=formed"
    exit 1
  fi
  echo "cluster-join: J11 link=$CLUSTER_STATIC_SELF_IP ceiling=${CLUSTER_WIRED_LIMIT_MB:-unset} rank_pid=${rank_pid:-unknown} held_pd=$held session=$JOIN_SESSION_ID decision=formed"
  formed=true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cluster_join_main "$@"
fi
