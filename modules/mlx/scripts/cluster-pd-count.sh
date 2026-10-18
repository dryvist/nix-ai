# shellcheck shell=bash
# Kernel RDMA protection-domain count.

# Results are consumed by the separate pd-gate layer after sourcing.
export PD_HELD PD_COUNT_DETAIL

pd_count_info() {
  local class="$1" output rc=0 display LC_ALL=C
  if output="$("${CLUSTER_IOCLASSCOUNT_BIN:-/usr/sbin/ioclasscount}" "$class" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  display="${output//$'\n'/ }"
  display="${display//$'\r'/ }"
  display="${display:0:200}"
  printf 'cluster-join: pd-count info class=%s rc=%s raw=%s\n' \
    "$class" "$rc" "${display:-<empty>}" >&2
}

# The class count must be a single exact record; zero exit alone is not proof.
pd_held_count() {
  local captured output rc display LC_ALL=C
  PD_HELD="?"
  PD_COUNT_DETAIL=""
  captured="$("${CLUSTER_IOCLASSCOUNT_BIN:-/usr/sbin/ioclasscount}" AppleThunderboltRDMAProtectionDomain 2>&1; printf '\034%s' "$?")"
  rc="${captured##*$'\034'}"
  output="${captured%$'\034'*}"
  pd_count_info AppleThunderboltRDMAQueuePair
  pd_count_info IORDMAFamilyUC

  display="${output//$'\n'/ }"
  display="${display//$'\r'/ }"
  display="${display:0:200}"
  case "$output" in
    *$'\n') output="${output%$'\n'}" ;;
  esac
  if [ "$rc" -eq 0 ] && [[ "$output" =~ ^AppleThunderboltRDMAProtectionDomain\ =\ ([0-9]+)$ ]]; then
    PD_HELD="${BASH_REMATCH[1]}"
    return 0
  fi
  PD_COUNT_DETAIL="ioclasscount rc=$rc raw=${display:-<empty>}"
  return 1
}
