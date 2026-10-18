# shellcheck shell=bash
# cluster-join -- guarded, one-shot cluster bring-up.

join_fail() {
  echo "cluster-join: FAIL: $*" >&2
  exit 1
}

cluster_model_refuse() {
  local detail="$1"
  detail="${detail//$'\n'/ }"
  detail="${detail//$'\r'/ }"
  printf 'cluster-join: REFUSE reason=model-not-cached detail=%s\n' "$detail" >&2
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
        printf 'cluster-join: REFUSE reason=model-too-large detail=snapshot size exceeds safe measurement range\n' >&2
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
      printf 'cluster-join: REFUSE reason=model-too-large detail=local wired ceiling is unconfigured\n' >&2
      return 1
    fi
    limit=$((10#$ceiling - 10#$reserve))
    if [ "$shard_mb" -gt "$limit" ]; then
      printf 'cluster-join: REFUSE reason=model-too-large shard_mb=%s ceiling_mb=%s\n' "$shard_mb" "$limit" >&2
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
  local -a join_args=(cluster-join --worker)
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

cluster_peer_ssh_running() {
  local pid
  while IFS= read -r pid; do
    [ "$pid" = "${CLUSTER_PEER_SSH_PID:-}" ] && return 0
  done < <(jobs -pr)
  return 1
}

cluster_peer_ssh_wait() {
  local deadline term_deadline rc timed_out=false
  [ -n "${CLUSTER_PEER_SSH_PID:-}" ] || return 0
  deadline=$((SECONDS + ${CLUSTER_JOIN_TIMEOUT_SECS:-600} + 30))
  while cluster_peer_ssh_running; do
    if [ "${JOIN_SIGNAL_RC:-0}" -ne 0 ]; then
      echo "cluster-join: peer-ssh stopping after signal rc=$JOIN_SIGNAL_RC" >&2
      break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      timed_out=true
      echo "cluster-join: peer-ssh timeout" >&2
      break
    fi
    sleep 1
  done
  if cluster_peer_ssh_running; then
    kill -TERM "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
    term_deadline=$((SECONDS + 5))
    while cluster_peer_ssh_running && [ "$SECONDS" -lt "$term_deadline" ]; do sleep 1; done
    if cluster_peer_ssh_running; then kill -KILL "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true; fi
  fi
  while cluster_peer_ssh_running; do sleep 1; done
  if wait "$CLUSTER_PEER_SSH_PID"; then rc=0; else rc=$?; fi
  CLUSTER_PEER_SSH_RC=$rc
  CLUSTER_PEER_SSH_PID=""
  echo "cluster-join: peer-ssh exit rc=$rc"
  [ "$timed_out" = false ] || return 0
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
      join_fail "stale swap (${used}M > ${threshold}M); reboot before joining"
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
  local rc=$? teardown_rc=0 peer_rc=0 peer_started=false
  JOIN_EXIT_ACTIVE=true
  trap - EXIT
  trap 'cluster_join_signal 130' INT
  trap 'cluster_join_signal 143' TERM
  if [ "$formed" != true ] && [ "$quiesced" = true ]; then
    cluster_teardown || teardown_rc=$?
    if [ "${JOIN_REBOOT:-0}" -eq 1 ] || [ "${TEARDOWN_REBOOT:-0}" -eq 1 ]; then
      rc=3
    elif [ "$rc" -eq 0 ] || [ "$teardown_rc" -ne 0 ]; then
      rc=1
    fi
  fi
  if [ -n "${CLUSTER_PEER_SSH_PID:-}" ]; then
    peer_started=true
    cluster_peer_ssh_wait
    peer_rc=$CLUSTER_PEER_SSH_RC
  fi
  if [ "$rc" -eq 0 ] && [ "$peer_started" = true ] && [ "$peer_rc" -ne 0 ]; then
    echo "cluster-join: REFUSE reason=peer-join-failed rc=$peer_rc" >&2
    teardown_rc=0
    cluster_teardown || teardown_rc=$?
    if [ "$peer_rc" -eq 3 ] || [ "$teardown_rc" -eq 3 ] || [ "${TEARDOWN_REBOOT:-0}" -eq 1 ]; then
      rc=3
    else
      rc=1
    fi
  elif [ "$rc" -eq 0 ] && [ "${JOIN_SIGNAL_RC:-0}" -ne 0 ]; then
    rc=$JOIN_SIGNAL_RC
  fi
  trap - INT TERM
  exit "$rc"
}

cluster_join_signal() {
  local signal_rc="$1"
  if [ "${JOIN_EXIT_ACTIVE:-false}" = true ]; then
    JOIN_SIGNAL_RC="$signal_rc"
  else
    exit "$signal_rc"
  fi
}

cluster_join_peer_poll() {
  if peer_armed_read; then
    JOIN_PEER_ARMED_AT="$PEER_ARMED_AT"
    return 0
  fi
  echo "cluster-join: peer-state REFUSE reason=${PEER_GATE_REASON:-unknown}"
  case "${PEER_GATE_REASON:-}" in
    generation-mismatch*) return 2 ;;
  esac
  return 1
}

cluster_start_at() {
  local own="$1" peer="$2" latest
  latest="$own"
  [ "$peer" -le "$own" ] || latest="$peer"
  printf '%s\n' "$((latest + 20))"
}

cluster_sleep_until() {
  local target="$1" now remaining
  now="$(date +%s)"
  while [ "$now" -lt "$target" ]; do
    remaining=$((target - now))
    sleep "$remaining"
    now="$(date +%s)"
  done
  [ "$now" -eq "$target" ]
}

cluster_final_rank_start() {
  local start_at="$1" expected_peer_armed_at="$2" now
  echo "cluster-join: J9 final peer and PD gates"
  if ! peer_armed_read; then
    echo "cluster-join: peer-state REFUSE reason=${PEER_GATE_REASON:-unknown}"
    return 1
  fi
  [ "$PEER_ARMED_AT" = "$expected_peer_armed_at" ] || {
    echo "cluster-join: peer-state REFUSE reason=peer-armed-at-changed" >&2
    return 1
  }
  if ! pd_start_gate; then
    return 1
  fi
  now="$(date +%s)"
  if [ "$now" -gt "$start_at" ]; then
    echo "cluster-join: REFUSE missed start window after final gates (now=$now start_at=$start_at)" >&2
    return 1
  fi
  cluster_sleep_until "$start_at" || {
    echo "cluster-join: REFUSE missed start window at kickstart" >&2
    return 1
  }
  cluster_rank_model_write || {
    echo "cluster-join: REFUSE reason=rank-model-write" >&2
    return 1
  }
  "${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}" kickstart "gui/$uid/${CLUSTER_RANK_LABEL}" || {
    echo "cluster-join: FAIL launchctl kickstart for ${CLUSTER_RANK_LABEL}" >&2
    return 1
  }
  echo "cluster-join: kickstart issued at $(date +%s)"
}

cluster_join_main() {
  local timeout deadline armed_at peer_armed_at start_at now poll_rc
  local launchctl_bin="${CLUSTER_LAUNCHCTL_BIN:-/bin/launchctl}"
  local rank_pid warm_ok=false stable_since=0 stable_required worker_invocation=false
  local model_explicit=false pipeline_requested=false model_arg="" selected_model
  local PEER_ARMED_AT=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worker)
        [ "$worker_invocation" = false ] || join_fail "usage: cluster-join [--worker] [--model org/repo] [--pipeline]"
        worker_invocation=true
        shift
        ;;
      --model)
        [ "$model_explicit" = false ] && [ "$#" -ge 2 ] || join_fail "usage: cluster-join [--worker] [--model org/repo] [--pipeline]"
        model_arg="$2"
        model_explicit=true
        shift 2
        ;;
      --pipeline)
        [ "$pipeline_requested" = false ] || join_fail "usage: cluster-join [--worker] [--model org/repo] [--pipeline]"
        pipeline_requested=true
        shift
        ;;
      *) join_fail "usage: cluster-join [--worker] [--model org/repo] [--pipeline]" ;;
    esac
  done
  [ "$pipeline_requested" = false ] || [ "$model_explicit" = true ] ||
    join_fail "usage: --pipeline requires --model"
  uid="$(id -u)"
  state_dir="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_STATE_FILE")}"
  mkdir -p "$state_dir"
  cluster_lifecycle_log_start
  [ "$worker_invocation" = false ] || echo "cluster-join: peer worker invocation accepted"
  formed=false
  quiesced=false
  JOIN_REBOOT=0
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  CLUSTER_PEER_SSH_PID=""
  CLUSTER_PEER_SSH_RC=0
  trap cluster_join_exit EXIT
  trap 'cluster_join_signal 130' INT
  trap 'cluster_join_signal 143' TERM

  selected_model="${CLUSTER_MODEL:-}"
  [ "$model_explicit" = false ] || selected_model="$model_arg"
  if ! cluster_join_model_select "$selected_model" "$model_explicit" "$pipeline_requested"; then
    exit 1
  fi

  echo "cluster-join: J1 pd-start-gate"
  if pd_start_gate; then
    :
  else
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
    join_fail "link prep is not ready; run sudo /nix/var/nix/profiles/system/activate"
  fi

  echo "cluster-join: J3 wired-ceiling"
  if set_wired_limit "${CLUSTER_WIRED_LIMIT_MB:-}"; then
    echo "cluster-join: wired-ceiling PASS"
  else
    join_fail "could not set the cluster wired ceiling"
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
    echo "cluster-join: room REFUSE detail=${MEM_HEADROOM_DETAIL:-unknown}" >&2
    case "${MEM_HEADROOM_DETAIL:-}" in *unreclaimed-Metal*) JOIN_REBOOT=1 ;; esac
    exit "$((JOIN_REBOOT == 1 ? 3 : 1))"
  fi

  cluster_peer_ssh_start

  echo "cluster-join: J6 arm"
  armed_at="$(date +%s)"
  if ! peer_state_write true "$armed_at" || ! link_state_write up; then
    join_fail "could not publish armed state"
  fi
  echo "cluster-join: decision=armed armed_at=$armed_at"

  timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}"
  deadline=$(($(date +%s) + timeout))
  echo "cluster-join: J7 peer poll timeout=${timeout}s"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if cluster_join_peer_poll; then
      peer_armed_at="$JOIN_PEER_ARMED_AT"
      echo "cluster-join: peer-state PASS armed_at=$peer_armed_at"
      break
    else
      poll_rc=$?
    fi
    [ "$poll_rc" -eq 2 ] && join_fail "$PEER_GATE_REASON"
    sleep 5
  done
  [ -n "${peer_armed_at:-}" ] || join_fail "peer never armed before join timeout"

  start_at="$(cluster_start_at "$armed_at" "$peer_armed_at")"
  echo "cluster-join: J8 start_at=$start_at"
  now="$(date +%s)"
  if [ "$now" -gt "$((start_at - 3))" ]; then
    join_fail "missed start window (now=$now start_at=$start_at)"
  fi
  cluster_sleep_until "$((start_at - 3))" || join_fail "missed start window before J9"

  if ! cluster_final_rank_start "$start_at" "$peer_armed_at"; then
    [ "${PD_REBOOT:-0}" -eq 1 ] && JOIN_REBOOT=1
    exit "$((JOIN_REBOOT == 1 ? 3 : 1))"
  fi

  echo "cluster-join: J10 formation check"
  timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}"
  deadline=$(($(date +%s) + timeout))
  if [ "$CLUSTER_ROLE" = coordinator ]; then
    stable_since="$(date +%s)"
    while [ "$(date +%s)" -lt "$deadline" ]; do
      if curl -fsS -m 5 "http://127.0.0.1:${CLUSTER_HTTP_PORT}/v1/models" > /dev/null 2>&1; then
        warm_ok=true
        break
      fi
      now="$(date +%s)"
      if ! rank_process_running && [ "$((now - stable_since))" -ge 15 ]; then
        join_fail "rank exited during formation"
      fi
      sleep 5
    done
    [ "$warm_ok" = true ] || join_fail "coordinator endpoint did not form within ${timeout}s"
  else
    stable_required="${CLUSTER_WORKER_STABLE_SECS:-60}"
    stable_since=0
    while [ "$(date +%s)" -lt "$deadline" ]; do
      if "$launchctl_bin" print "gui/$uid/${CLUSTER_RANK_LABEL}" 2> /dev/null |
        "${CLUSTER_GREP_BIN:-/usr/bin/grep}" -q 'state = running' && rank_process_running; then
        [ "$stable_since" -gt 0 ] || stable_since="$(date +%s)"
        now="$(date +%s)"
        if [ "$((now - stable_since))" -ge "$stable_required" ]; then
          warm_ok=true
          break
        fi
      else
        stable_since=0
        now="$(date +%s)"
        if [ "$now" -ge "$((deadline - timeout + 15))" ] && ! rank_process_running; then
          join_fail "worker rank exited during formation"
        fi
      fi
      sleep 5
    done
    [ "$warm_ok" = true ] || join_fail "worker rank did not stay up for ${stable_required}s"
  fi

  rank_pid="$(rank_process_pids 2> /dev/null | head -n 1 || true)"
  if pd_held_count; then held="$PD_HELD"; else held="?"; fi
  echo "cluster-join: J11 link=$CLUSTER_STATIC_SELF_IP ceiling=${CLUSTER_WIRED_LIMIT_MB:-unset} rank_pid=${rank_pid:-unknown} held_pd=$held decision=formed"
  formed=true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cluster_join_main "$@"
fi
