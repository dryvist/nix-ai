# shellcheck shell=bash
# Shared by the schedule agents: one decision-log format and the clustered test.

# One decision line per guard. The schedule logs are read by this exact format.
schedule_log() {
  printf 'cluster-schedule: guard=%s decision=%s reason=%s\n' "$1" "$2" "$3"
}

# Sets SCHEDULE_CLUSTER_DETAIL and returns:
#   0 = clustered: the rank is live, or the link is up and this host's peer state is armed
#   1 = not clustered
#   2 = unanswerable: the rank probe gave no answer, so the caller must fail closed
schedule_clustered() {
  local link armed
  SCHEDULE_CLUSTER_DETAIL=""
  if rank_process_running; then
    SCHEDULE_CLUSTER_DETAIL="rank-live"
    return 0
  fi
  if ! rank_process_absent; then
    SCHEDULE_CLUSTER_DETAIL="rank-probe-unanswerable"
    return 2
  fi
  link="$(cat "$CLUSTER_STATE_FILE" 2> /dev/null || echo down)"
  armed="$(jq -r '.armed // false' "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || echo false)"
  SCHEDULE_CLUSTER_DETAIL="link=$link peer-armed=$armed"
  if [ "$link" = up ] && [ "$armed" = true ]; then
    return 0
  fi
  return 1
}
