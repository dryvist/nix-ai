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
  local configured="${CLUSTER_PD_DEVICE_BUDGET:-}" log_prefix=cluster-link
  [ "${0##*/}" != cluster-join ] || log_prefix=cluster-join
  local device output rc=0 reported LC_ALL=C
  [[ "$configured" =~ ^[0-9]{1,4}$ ]] || {
    PD_BUDGET_DETAIL="configured devicePdBudget is not a bounded decimal"
    return 1
  }
  [ "$((10#$configured))" -gt 0 ] || {
    PD_BUDGET_DETAIL="configured devicePdBudget must be positive"
    return 1
  }
  if ! device="$(active_rdma_device)"; then
    PD_BUDGET_DETAIL="no carrier-active RDMA device found to verify max_pd against"
    return 1
  fi
  if output="$("${CLUSTER_IBV_DEVINFO_BIN:-/usr/bin/ibv_devinfo}" -d "$device" -v 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    PD_BUDGET_DETAIL="ibv_devinfo -d $device -v rc=$rc; max_pd budget unverified"
    return 1
  fi
  if ! reported="$(LC_ALL=C awk '
    $1 == "max_pd:" {
      records++
      if (NF != 2 || $2 !~ /^[0-9]+$/ || length($2) > 4) {
        invalid = 1
        next
      }
      value = $2 + 0
      if (records == 1) first = value
      else if (value != first) invalid = 1
    }
    END { if (records > 0 && !invalid) printf "%d\n", first; else exit 1 }
  ' <<< "$output")"; then
    PD_BUDGET_DETAIL="ibv_devinfo -d $device -v has missing, inconsistent, or unbounded max_pd records"
    return 1
  fi
  if [ "$reported" -lt "$((10#$configured))" ]; then
    PD_BUDGET_DETAIL="$device reports max_pd=$reported, below the configured devicePdBudget=$configured — the reserve invariant would be evaluated against a budget the device does not have"
    return 1
  fi
  if [ "$reported" -gt "$((10#$configured))" ]; then
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

  if ! [[ "$budget" =~ ^[0-9]{1,4}$ ]] || ! [[ "$reserve" =~ ^[0-9]{1,4}$ ]]; then
    pd_gate_refuse pd-gate-unconfigured 'budget and reserve must be bounded decimals with 0 < reserve < budget'
    return 1
  fi
  budget_num=$((10#$budget))
  reserve_num=$((10#$reserve))
  if [ "$budget_num" -le 0 ] || [ "$reserve_num" -le 0 ] || [ "$reserve_num" -ge "$budget_num" ]; then
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

  if ! [[ "${PD_HELD:-}" =~ ^[0-9]{1,4}$ ]]; then
    PD_HELD="?"
    pd_gate_refuse pd-count-unreadable 'held PD count is not a bounded decimal'
    return 1
  fi
  held_num=$((10#$PD_HELD))
  if [ "$held_num" -gt "$budget_num" ]; then
    pd_gate_refuse pd-count-unreadable "held PD count $PD_HELD exceeds the configured budget $budget"
    return 1
  fi
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
