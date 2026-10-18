# shellcheck shell=bash
# Shared RDMA budget gate functions.

# The caller uses this to choose its exit code after a refusal.
export PD_REBOOT

# The carrier-active Thunderbolt port's RDMA device (e.g. "rdma_en2"), same
# discovery cluster-rank-launch.sh uses for the ibv matrix — never a pinned
# name, because moving the cable moves the port. Falls back to
# CLUSTER_RDMA_DEVICE (already prefixed) when no carrier-active port has a
# matching rdma_<dev>.
active_rdma_device() {
  local dev
  while read -r dev; do
    [ -n "$dev" ] || continue
    /sbin/ifconfig "$dev" 2>/dev/null | /usr/bin/grep -q 'status: active' || continue
    if /usr/bin/ibv_devices 2>/dev/null | /usr/bin/awk '{print $1}' | /usr/bin/grep -qx "rdma_$dev"; then
      printf 'rdma_%s\n' "$dev"
      return 0
    fi
  done < <(
    /usr/sbin/networksetup -listallhardwareports 2>/dev/null |
      /usr/bin/awk '/^Hardware Port: Thunderbolt [0-9]/ { tb = 1; next }
           /^Device:/ { if (tb) print $2; tb = 0 }'
  )
  [ -n "${CLUSTER_RDMA_DEVICE:-}" ] || return 1
  printf '%s\n' "$CLUSTER_RDMA_DEVICE"
}

# #1442: devicePdBudget (CLUSTER_PD_DEVICE_BUDGET) is a measured constant frozen
# into Nix at eval time. ibv_devinfo cannot run in the Nix sandbox, so compare
# the configured value with this host's device at runtime.
#
# Sets PD_BUDGET_DETAIL for the caller's log line. Fail-closed, matching every
# other rung in this file: an unreadable probe is treated as unverified, not as
# passing, because "silently inert while reporting success" is the exact defect
# class this guard exists to catch (see file header).
pd_device_budget_ok() {
  local configured="${CLUSTER_PD_DEVICE_BUDGET:-0}" log_prefix=cluster-link
  [ "${0##*/}" != cluster-join ] || log_prefix=cluster-join
  local device reported
  case "$configured" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [ "$configured" -gt 0 ] || return 0
  if ! device="$(active_rdma_device)"; then
    PD_BUDGET_DETAIL="no carrier-active RDMA device found to verify max_pd against"
    return 1
  fi
  reported="$("${CLUSTER_IBV_DEVINFO_BIN:-/usr/bin/ibv_devinfo}" -d "$device" -v 2>/dev/null | /usr/bin/awk '$1 == "max_pd:" { print $2; exit }')"
  case "$reported" in
    '' | *[!0-9]*)
      PD_BUDGET_DETAIL="ibv_devinfo -d $device -v did not report a readable max_pd; budget unverified"
      return 1
      ;;
  esac
  if [ "$reported" -lt "$configured" ]; then
    PD_BUDGET_DETAIL="$device reports max_pd=$reported, below the configured devicePdBudget=$configured — the reserve invariant would be evaluated against a budget the device does not have"
    return 1
  fi
  if [ "$reported" -gt "$configured" ]; then
    echo "$log_prefix: $device reports max_pd=$reported, above the configured devicePdBudget=$configured (conservative; not refusing)" >&2
  fi
  return 0
}

pd_gate_log() {
  local verdict="$1" detail="$2"
  local budget="${CLUSTER_PD_DEVICE_BUDGET:-?}" reserve="${CLUSTER_PD_RESERVE:-?}"
  detail="${detail//$'\n'/ }"
  detail="${detail//$'\r'/ }"
  budget="${budget//$'\n'/ }"
  budget="${budget//$'\r'/ }"
  reserve="${reserve//$'\n'/ }"
  reserve="${reserve//$'\r'/ }"
  printf 'cluster-join: pd-gate %s reason=%s held=%s budget=%s reserve=%s detail=%s\n' \
    "$verdict" "${PD_GATE_REASON:-unknown}" "${PD_HELD:-?}" \
    "$budget" "$reserve" "$detail" >&2
}

pd_gate_refuse() {
  PD_GATE_REASON="$1"
  pd_gate_log REFUSE "$2"
  return 1
}

# Return success only when the rank absence and measured PD count leave reserve.
pd_start_gate() {
  local budget="${CLUSTER_PD_DEVICE_BUDGET:-}" reserve="${CLUSTER_PD_RESERVE:-}"
  local pids probe_rc=0 budget_num reserve_num held_num available_num
  PD_GATE_REASON=""
  PD_HELD="?"
  PD_REBOOT=0

  case "$budget" in
    '' | *[!0-9]*) pd_gate_refuse pd-gate-unconfigured 'budget and reserve must be integers with 0 < reserve < budget'; return 1 ;;
  esac
  case "$reserve" in
    '' | *[!0-9]*) pd_gate_refuse pd-gate-unconfigured 'budget and reserve must be integers with 0 < reserve < budget'; return 1 ;;
  esac
  if [ "$budget" -le 0 ] || [ "$reserve" -le 0 ] || [ "$reserve" -ge "$budget" ]; then
    pd_gate_refuse pd-gate-unconfigured 'budget and reserve must be integers with 0 < reserve < budget'
    return 1
  fi

  if [ -z "${CLUSTER_RANK_PROCESS_PATTERN:-}" ]; then
    pd_gate_refuse rank-probe-unanswerable 'CLUSTER_RANK_PROCESS_PATTERN is unset'
    return 1
  fi

  if pids="$(rank_process_pids)"; then
    probe_rc=0
  else
    probe_rc=$?
  fi
  case "$probe_rc" in
    0)
      pd_gate_refuse rank-alive "pids=${pids:-unknown}"
      return 1
      ;;
    1) ;;
    *)
      pd_gate_refuse rank-probe-unanswerable "pgrep rc=$probe_rc"
      return 1
      ;;
  esac

  if ! pd_device_budget_ok; then
    pd_gate_refuse device-budget-unverified "${PD_BUDGET_DETAIL:-max_pd could not be verified}"
    return 1
  fi
  if ! pd_held_count; then
    pd_gate_refuse pd-count-unreadable "$PD_COUNT_DETAIL"
    return 1
  fi

  budget_num=$((10#$budget))
  reserve_num=$((10#$reserve))
  held_num=$((10#$PD_HELD))
  available_num=$((budget_num - reserve_num))
  if [ $((held_num + 1)) -ge "$available_num" ]; then
    PD_REBOOT=1
    pd_gate_refuse pd-reserve 'the next rank PD would reach the configured reserve'
    return 1
  fi

  PD_GATE_REASON=pd-reserve-available
  if [ "$PD_HELD" -gt 0 ]; then
    if ! pd_gate_log PASS "WARN held=$PD_HELD with no rank alive"; then
      return 1
    fi
  else
    if ! pd_gate_log PASS 'no PDs held with no rank alive'; then
      return 1
    fi
  fi
  return 0
}
