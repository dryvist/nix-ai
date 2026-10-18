# shellcheck shell=bash
# cluster-join -- peer link preflight.

# The peer address is the only channel available before the ranks start, so this
# bounded check reports an unanswered peer as unverified instead of diagnosing it.

peer_link_preflight() {
  local timeout_secs="${CLUSTER_PEER_READY_TIMEOUT_SECS:-120}"
  local poll="${CLUSTER_PEER_READY_POLL_SECS:-5}"
  local deadline
  deadline=$(($(date +%s) + timeout_secs))
  while :; do
    if peer_reachable; then
      return 0
    fi
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep "$poll"
  done
}
