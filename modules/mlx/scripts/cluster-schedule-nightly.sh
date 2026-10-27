# shellcheck shell=bash
# Nightly agent body, coordinator only. It runs the read-only preflight, then the
# existing coordinator join on a pass. One run per launchd fire. It never retries
# and never reboots. A join exit 3 is logged and propagated.

schedule_nightly_main() {
  local rc=0
  echo "cluster-schedule: nightly start CLUSTER_INVOKER=${CLUSTER_INVOKER:-manual}"
  if "$CLUSTER_SCHEDULE_PREFLIGHT_BIN"; then
    :
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      echo "cluster-schedule: nightly decision=hold reason=preflight-held"
      return 0
    fi
    echo "cluster-schedule: nightly decision=error reason=preflight-rc=$rc"
    return 1
  fi
  echo "cluster-schedule: nightly decision=join"
  if "$CLUSTER_JOIN_BIN"; then
    echo "cluster-schedule: nightly join rc=0"
    return 0
  else
    rc=$?
  fi
  if [ "$rc" -eq 3 ]; then
    echo "cluster-schedule: nightly join rc=3 reason=reboot-required; not rebooting, not retrying"
    return 3
  fi
  echo "cluster-schedule: nightly join rc=$rc reason=join-failed; not retrying"
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  schedule_nightly_main "$@"
fi
