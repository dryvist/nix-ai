# shellcheck shell=bash
# cluster-detach -- stop this rank, restore standalone serving and verify it.

cluster_detach_main() {
  local timeout deadline failed=0 peer_detach_rc=0 used swap_threshold stale_swap=false
  local current link_state serve_ok=false body held="?" rc worker_invocation=false
  local session_arg="" current_session
  state_dir="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_STATE_FILE")}"
  mkdir -p "$state_dir"
  export CLUSTER_LIFECYCLE_COMPONENT=cluster-detach
  cluster_lifecycle_log_start
  trap 'cluster_lifecycle_lock_release' EXIT
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worker)
        [ "$worker_invocation" = false ] || { lifecycle_refuse usage "cluster-detach [--worker [--session ID]]"; exit 1; }
        worker_invocation=true
        shift
        ;;
      --session)
        [ -z "$session_arg" ] && [ "$#" -ge 2 ] || { lifecycle_refuse usage "cluster-detach [--worker [--session ID]]"; exit 1; }
        session_arg="$2"
        shift 2
        ;;
      *) lifecycle_refuse usage "cluster-detach [--worker [--session ID]]"; exit 1 ;;
    esac
  done
  if [ -n "$session_arg" ] && {
    [ "$worker_invocation" = true ] &&
      [[ "$session_arg" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]]
  }; then
    :
  elif [ -n "$session_arg" ]; then
    lifecycle_refuse usage "--session requires --worker and a valid session id"
    exit 1
  fi
  [ "$worker_invocation" = false ] || [ "${CLUSTER_ROLE:-}" = worker ] || {
    lifecycle_refuse usage "--worker is only valid on the worker role"
    exit 1
  }
  if ! cluster_lifecycle_lock_acquire; then
    lifecycle_refuse lifecycle-locked "another cluster lifecycle transaction owns $state_dir"
    exit 1
  fi
  if [ -n "$session_arg" ]; then
    current_session="$(jq -r '.session // ""' "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || true)"
    if [ "$current_session" != "$session_arg" ]; then
      lifecycle_refuse peer-session-mismatch "requested cleanup session $session_arg is not current"
      exit 1
    fi
  fi
  timeout="${CLUSTER_DETACH_TIMEOUT_SECS:-300}"
  [ "$worker_invocation" = false ] || echo "cluster-detach: peer worker invocation accepted"

  echo "cluster-detach: D1 local teardown"
  if cluster_teardown "$session_arg"; then
    echo "cluster-detach: teardown complete"
  else
    lifecycle_refuse teardown-failed "cluster teardown reported a failure"
    failed=1
  fi

  if [ "${CLUSTER_ROLE:-}" = coordinator ] && [ -n "${CLUSTER_PEER_SSH:-}" ]; then
    echo "cluster-detach: peer-ssh detaching worker"
    if "${CLUSTER_SSH_BIN:-/usr/bin/ssh}" -o BatchMode=yes -o ConnectTimeout=10 \
      "$CLUSTER_PEER_SSH" cluster-detach --worker; then
      echo "cluster-detach: peer-ssh peer-detach-succeeded"
    else
      rc=$?
      peer_detach_rc=$rc
      lifecycle_refuse peer-detach-failed "worker detach failed (rc=$rc)"
    fi
  fi

  echo "cluster-detach: D2 standalone real-completion probe"
  if [ -n "${CLUSTER_STANDALONE_PROBE_URL:-}" ]; then
    deadline=$(($(date +%s) + timeout))
    while [ "$(date +%s)" -lt "$deadline" ]; do
      if curl -fsS -m 5 "${CLUSTER_STANDALONE_PROBE_URL}/models" > /dev/null 2>&1; then
        body="$(curl -fsS -m 240 -X POST "${CLUSTER_STANDALONE_PROBE_URL}/chat/completions" \
          -H 'Content-Type: application/json' \
          -d "$(jq -nc --arg m "${CLUSTER_STANDALONE_PROBE_MODEL:-}" \
            '{model:$m,messages:[{role:"user",content:"ping"}],max_tokens:4}')" 2> /dev/null)" || body=""
        if jq -e '(.usage.completion_tokens // 0) >= 1' > /dev/null 2>&1 <<< "$body"; then
          serve_ok=true
          break
        fi
      fi
      sleep 10
    done
    if [ "$serve_ok" = true ]; then
      echo "cluster-detach: standalone serving restored (real completion verified)"
    else
      lifecycle_refuse serving-not-restored "standalone serving did not return a real completion within ${timeout}s"
      failed=1
    fi
  else
    lifecycle_refuse serving-probe-unconfigured "no standalone probe URL; serving cannot be verified"
    failed=1
  fi

  echo "cluster-detach: D3 swap check"
  used="$("${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}" -n vm.swapusage 2> /dev/null | /usr/bin/sed -n 's/.*used = \([0-9][0-9]*\).*/\1/p' || true)"
  used="${used:-0}"
  swap_threshold="${CLUSTER_DETACH_SWAP_THRESHOLD_MB:-20000}"
  if [ "$used" -gt "$swap_threshold" ]; then
    stale_swap=true
    lifecycle_refuse stale-swap "used=${used}M exceeds threshold=${swap_threshold}M"
  fi

  echo "cluster-detach: D4 summary"
  current="$("${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}" -n iogpu.wired_limit_mb 2> /dev/null || echo '?')"
  link_state="$(cat "$CLUSTER_STATE_FILE" 2> /dev/null || echo unknown)"
  if pd_held_count; then
    held="$PD_HELD"
  else
    lifecycle_refuse pd-count-unreadable "held PD count is unknown: ${PD_COUNT_DETAIL:-unreadable}"
    failed=1
  fi
  echo "cluster-detach $([ "$failed" -eq 0 ] && echo OK || echo FAIL) ($CLUSTER_ROLE)"
  echo "  link-state : $link_state"
  echo "  rank       : $(rank_process_absent && echo stopped || echo present-or-unknown)"
  echo "  wired ceil : $current (standalone ${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0})"
  echo "  held PDs   : $held of ${CLUSTER_PD_DEVICE_BUDGET:-?}"
  echo "  serving    : $([ "$serve_ok" = true ] && echo restored || echo NOT-VERIFIED)"
  echo "  swap used  : ${used}M (threshold ${swap_threshold}M)"

  cluster_detach_finish "$failed" "$peer_detach_rc" "${TEARDOWN_REBOOT:-0}" "$stale_swap"
}

cluster_detach_finish() {
  local failed="$1" peer_detach_rc="$2" reboot="$3" stale_swap="$4"
  if [ "$peer_detach_rc" -ne 0 ]; then
    [ "$peer_detach_rc" -eq 3 ] && exit 3
    exit 1
  fi
  if [ "$reboot" -eq 1 ] || [ "$stale_swap" = true ]; then
    exit 3
  fi
  [ "$failed" -eq 0 ] || exit 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cluster_detach_main "$@"
fi
