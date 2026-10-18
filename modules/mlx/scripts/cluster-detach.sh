# shellcheck shell=bash
# cluster-detach -- stop this rank, restore standalone serving and verify it.

cluster_detach_main() {
  local timeout deadline failed=0 peer_detach_failed=false used swap_threshold stale_swap=false
  local current link_state serve_ok=false body held="?" rc worker_invocation=false
  case "${1:-}" in
    "") ;;
    --worker) worker_invocation=true ;;
    *) echo "cluster-detach: FAIL: usage: cluster-detach [--worker]" >&2; exit 1 ;;
  esac
  [ "$#" -le 1 ] || { echo "cluster-detach: FAIL: usage: cluster-detach [--worker]" >&2; exit 1; }
  state_dir="${CLUSTER_STATE_DIR:-$(dirname "$CLUSTER_STATE_FILE")}"
  timeout="${CLUSTER_DETACH_TIMEOUT_SECS:-300}"
  mkdir -p "$state_dir"
  cluster_lifecycle_log_start
  [ "$worker_invocation" = false ] || echo "cluster-detach: peer worker invocation accepted"

  echo "cluster-detach: D1 local teardown"
  if cluster_teardown; then
    echo "cluster-detach: teardown complete"
  else
    echo "cluster-detach: teardown reported a failure" >&2
    failed=1
  fi

  if [ "${CLUSTER_ROLE:-}" = coordinator ] && [ -n "${CLUSTER_PEER_SSH:-}" ]; then
    echo "cluster-join: peer-ssh detaching worker"
    if "${CLUSTER_SSH_BIN:-/usr/bin/ssh}" -o BatchMode=yes -o ConnectTimeout=10 \
      "$CLUSTER_PEER_SSH" cluster-detach --worker; then
      echo "cluster-join: peer-ssh peer-detach-succeeded"
    else
      rc=$?
      echo "cluster-join: peer-ssh peer-detach-failed rc=$rc" >&2
      peer_detach_failed=true
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
      echo "cluster-detach: FAIL standalone serving did not return a real completion within ${timeout}s" >&2
      failed=1
    fi
  else
    echo "cluster-detach: FAIL no standalone probe URL; serving cannot be verified" >&2
    failed=1
  fi

  echo "cluster-detach: D3 swap check"
  used="$("${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}" -n vm.swapusage 2> /dev/null | /usr/bin/sed -n 's/.*used = \([0-9][0-9]*\).*/\1/p' || true)"
  used="${used:-0}"
  swap_threshold="${CLUSTER_DETACH_SWAP_THRESHOLD_MB:-20000}"
  [ "$used" -gt "$swap_threshold" ] && stale_swap=true

  echo "cluster-detach: D4 summary"
  current="$("${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}" -n iogpu.wired_limit_mb 2> /dev/null || echo '?')"
  link_state="$(cat "$CLUSTER_STATE_FILE" 2> /dev/null || echo unknown)"
  if pd_held_count; then
    held="$PD_HELD"
  else
    echo "cluster-detach: PD held=UNKNOWN detail=${PD_COUNT_DETAIL:-unreadable}" >&2
    failed=1
  fi
  echo "cluster-detach $([ "$failed" -eq 0 ] && echo OK || echo FAIL) ($CLUSTER_ROLE)"
  echo "  link-state : $link_state"
  echo "  rank       : $(rank_process_absent && echo stopped || echo present-or-unknown)"
  echo "  wired ceil : $current (standalone ${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0})"
  echo "  held PDs   : $held of ${CLUSTER_PD_DEVICE_BUDGET:-?}"
  echo "  serving    : $([ "$serve_ok" = true ] && echo restored || echo NOT-VERIFIED)"
  echo "  swap used  : ${used}M (threshold ${swap_threshold}M)"

  cluster_detach_finish "$failed" "$peer_detach_failed" "${TEARDOWN_REBOOT:-0}" "$stale_swap"
}

cluster_detach_finish() {
  local failed="$1" peer_detach_failed="$2" reboot="$3" stale_swap="$4"
  [ "$peer_detach_failed" = false ] || exit 3
  [ "$failed" -eq 0 ] || exit 1
  [ "$reboot" -eq 1 ] && exit 3
  [ "$stale_swap" = false ] || exit 3
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cluster_detach_main "$@"
fi
