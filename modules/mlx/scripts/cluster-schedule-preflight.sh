# shellcheck shell=bash
# Nightly preflight for the scheduled join. It runs every guard that can run
# without changing this host or its peer. It is read-only: it never quiesces,
# arms, kickstarts, writes link-state, or starts a rank.
#
# Exit 0 = every guard passed. Exit 1 = hold, nothing touched. It never exits 3.
#
# Guards run in order and stop at the first hold. Each guard prints one line:
#   cluster-schedule: guard=<N0..N3> decision=<pass|hold> reason=<TOKEN>
# Some guards also print a "detail=" line first. The guard= line is the one to parse.
#
# Consumed environment: the cluster common env, plus
#   CLUSTER_SCHEDULE_NIGHT_START_MIN / CLUSTER_SCHEDULE_DAY_START_MIN  minutes after midnight
#   CLUSTER_SCHEDULE_SWAP_THRESHOLD_MB                                  swap ceiling in MiB

# N0: only inside the night window. launchd runs a missed job when the Mac wakes.
# This guard stops a late wake from starting a join in the daytime.
schedule_guard_night_window() {
  local hhmm now night day in_window=false
  hhmm="$(date +%H%M)"
  now=$((10#${hhmm:0:2} * 60 + 10#${hhmm:2:2}))
  night="${CLUSTER_SCHEDULE_NIGHT_START_MIN:-}"
  day="${CLUSTER_SCHEDULE_DAY_START_MIN:-}"
  if ! [[ "$night" =~ ^[0-9]{1,4}$ && "$day" =~ ^[0-9]{1,4}$ ]]; then
    schedule_log N0 hold window-unconfigured
    return 1
  fi
  night=$((10#$night))
  day=$((10#$day))
  if [ "$night" -eq "$day" ]; then
    schedule_log N0 hold window-unconfigured
    return 1
  fi
  # The window wraps midnight when it starts later than it ends.
  if [ "$night" -lt "$day" ]; then
    if [ "$now" -ge "$night" ] && [ "$now" -lt "$day" ]; then in_window=true; fi
  else
    if [ "$now" -ge "$night" ] || [ "$now" -lt "$day" ]; then in_window=true; fi
  fi
  echo "cluster-schedule: N0 detail=now=${now}m window=${night}m-${day}m"
  if [ "$in_window" = true ]; then
    schedule_log N0 pass in-night-window
    return 0
  fi
  schedule_log N0 hold outside-night-window
  return 1
}

# N1: this host must not already be clustered. A live rank, or a link that is up
# with this host's peer state armed, means a join already ran or is running.
schedule_guard_mode() {
  local rc=0
  if schedule_clustered; then
    echo "cluster-schedule: N1 detail=$SCHEDULE_CLUSTER_DETAIL"
    schedule_log N1 hold already-clustered
    return 1
  else
    rc=$?
  fi
  if [ "$rc" -eq 2 ]; then
    echo "cluster-schedule: N1 detail=$SCHEDULE_CLUSTER_DETAIL"
    schedule_log N1 hold rank-probe-unanswerable
    return 1
  fi
  schedule_log N1 pass not-clustered
  return 0
}

# The peer GET is the same request cluster-join makes at J7, to the same responder.
# Both ends only read their state file, so the request has no side effect.
schedule_fetch_peer() {
  local body
  SCHEDULE_PEER_RAW=""
  body="$("${CLUSTER_CURL_BIN:-/usr/bin/curl}" -fsS -m "${CLUSTER_PEER_STATE_TIMEOUT_SECS:-2}" \
    "http://${CLUSTER_STATIC_PEER_IP}:${CLUSTER_PEER_STATE_PORT}/" 2> /dev/null)" || return 1
  [ -n "$body" ] || return 1
  printf '%s' "$body" | jq -e 'type == "object"' > /dev/null 2>&1 || return 1
  SCHEDULE_PEER_RAW="$body"
}

# The same rule as peer_version_value_known in cluster-peer-state-write.sh. A value
# that is empty, null, unknown, or a dirty build cannot be compared.
schedule_value_known() {
  case "$1" in
    '' | [Nn][Uu][Ll][Ll] | [Uu][Nn][Kk][Nn][Oo][Ww][Nn] | *[Dd][Ii][Rr][Tt][Yy]*) return 1 ;;
    *) return 0 ;;
  esac
}

# This host's value for one version key, as the join would publish it.
schedule_local_value() {
  case "$1" in
    macos) "${CLUSTER_SW_VERS_BIN:-/usr/bin/sw_vers}" -buildVersion 2> /dev/null || true ;;
    configuration_revision)
      "${CLUSTER_DARWIN_VERSION_BIN:-/run/current-system/sw/bin/darwin-version}" --json 2> /dev/null |
        jq -r '.configurationRevision // empty' 2> /dev/null || true
      ;;
    *) jq -r --arg key "$1" '.[$key] // ""' <<< "${CLUSTER_SOFTWARE_JSON:-}" 2> /dev/null || true ;;
  esac
}

# N2: the peer must answer, must not be armed, and must run this host's generation.
# A generation is the darwin configuration revision plus the pinned software keys.
# A value the peer has not published yet is deferred to the join, not held here.
# A rebooted peer resets its state until a join writes it again. Holding on that
# blank would wait forever. The join checks every key at J8, before kickstart.
schedule_guard_peer() {
  local key local_value peer_value rev_local rev_peer armed deferred=""
  if ! schedule_fetch_peer; then
    schedule_log N2 hold peer-unreachable
    return 1
  fi
  armed="$(jq -r '.armed // false' <<< "$SCHEDULE_PEER_RAW" 2> /dev/null || echo false)"
  if [ "$armed" = true ]; then
    schedule_log N2 hold peer-armed
    return 1
  fi
  rev_local="$(schedule_local_value configuration_revision)"
  if ! schedule_value_known "$rev_local"; then
    echo "cluster-schedule: N2 detail=local configuration revision unreadable"
    schedule_log N2 hold generation-unknown-local
    return 1
  fi
  rev_peer="$(jq -r '.configuration_revision // ""' <<< "$SCHEDULE_PEER_RAW" 2> /dev/null || true)"
  if ! schedule_value_known "$rev_peer"; then
    deferred="configuration_revision"
  elif [ "$rev_peer" != "$rev_local" ]; then
    echo "cluster-schedule: N2 detail=configuration revision local=$rev_local peer=$rev_peer"
    schedule_log N2 hold generation-mismatch
    return 1
  fi
  # model_revision is left out on purpose. The join resolves it from the local
  # model cache, and the software contract carries it empty until then.
  for key in nix_ai mlx mlx_lm macos model; do
    local_value="$(schedule_local_value "$key")"
    if ! schedule_value_known "$local_value"; then
      echo "cluster-schedule: N2 detail=key=$key unreadable on this host"
      schedule_log N2 hold version-unknown-local
      return 1
    fi
    peer_value="$(jq -r --arg key "$key" '.software[$key] // ""' <<< "$SCHEDULE_PEER_RAW" 2> /dev/null || true)"
    if ! schedule_value_known "$peer_value"; then
      deferred="$deferred $key"
    elif [ "$peer_value" != "$local_value" ]; then
      echo "cluster-schedule: N2 detail=key=$key local=$local_value peer=$peer_value"
      schedule_log N2 hold version-mismatch
      return 1
    fi
  done
  if [ -n "$deferred" ]; then
    echo "cluster-schedule: N2 detail=deferred to join:$deferred"
    schedule_log N2 pass generation-deferred
    return 0
  fi
  schedule_log N2 pass generation-match
  return 0
}

# N3: swap under the threshold, then the protection-domain start gate. Both are the
# checks cluster-join runs before its first shared step.
# The wired-room check is not here. cluster-join runs it after quiesce, at J5 and
# again at J9. Run before quiesce, it would count standalone serving memory and
# read the standalone wired ceiling, which is 0 on a default host.
schedule_guard_host() {
  local used threshold
  used="$("${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}" -n vm.swapusage 2> /dev/null |
    "${CLUSTER_SED_BIN:-/usr/bin/sed}" -n 's/.*used = \([0-9][0-9]*\).*/\1/p' || true)"
  case "$used" in
    '' | *[!0-9]*)
      schedule_log N3 hold swap-unreadable
      return 1
      ;;
  esac
  threshold="${CLUSTER_SCHEDULE_SWAP_THRESHOLD_MB:-}"
  if ! [[ "$threshold" =~ ^[0-9]{1,6}$ ]]; then
    schedule_log N3 hold swap-threshold-unconfigured
    return 1
  fi
  if [ "$((10#$used))" -gt "$((10#$threshold))" ]; then
    echo "cluster-schedule: N3 detail=used=${used}M threshold=${threshold}M"
    schedule_log N3 hold swap-over-threshold
    return 1
  fi
  schedule_log N3 pass swap-under-threshold
  if ! pd_start_gate; then
    schedule_log N3 hold "${PD_GATE_REASON:-pd-gate-refused}"
    return 1
  fi
  schedule_log N3 pass "${PD_GATE_REASON:-pd-reserve-available}"
  return 0
}

schedule_preflight_main() {
  echo "cluster-schedule: preflight start CLUSTER_INVOKER=${CLUSTER_INVOKER:-manual}"
  schedule_guard_night_window || return 1
  schedule_guard_mode || return 1
  schedule_guard_peer || return 1
  schedule_guard_host || return 1
  echo "cluster-schedule: preflight decision=pass"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  schedule_preflight_main "$@"
fi
