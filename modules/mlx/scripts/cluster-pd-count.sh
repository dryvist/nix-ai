# shellcheck shell=bash
# Kernel RDMA protection-domain count.

# Results are consumed by the separate pd-gate layer after sourcing.
export PD_HELD PD_COUNT_DETAIL

pd_count_info() {
  local class="$1" output rc=0 display prefix=cluster-join LC_ALL=C
  [ "${0##*/}" != cluster-detach ] || prefix=cluster-detach
  if output="$(LC_ALL=C "${CLUSTER_IOCLASSCOUNT_BIN:-/usr/sbin/ioclasscount}" "$class" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  display="${output//$'\n'/ }"
  display="${display//$'\r'/ }"
  display="${display:0:200}"
  printf '%s: pd-count info class=%s rc=%s raw=%s\n' "$prefix" \
    "$class" "$rc" "${display:-<empty>}" >&2
}

# The class count must be a single exact record; zero exit alone is not proof.
pd_held_count() {
  local rc=0 display byte_dump tmp parsed
  PD_HELD="?"
  PD_COUNT_DETAIL=""
  pd_count_info AppleThunderboltRDMAQueuePair
  pd_count_info IORDMAFamilyUC

  if ! tmp="$(mktemp "${TMPDIR:-/tmp}/cluster-pd-count.XXXXXX")"; then
    PD_COUNT_DETAIL="ioclasscount output could not be captured"
    return 1
  fi
  if LC_ALL=C "${CLUSTER_IOCLASSCOUNT_BIN:-/usr/sbin/ioclasscount}" \
    AppleThunderboltRDMAProtectionDomain > "$tmp" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  display="$(head -c 200 "$tmp" | LC_ALL=C tr -c '\012\040-\176' '?')"
  display="${display//$'\n'/ }"
  display="${display//$'\r'/ }"
  if ! byte_dump="$(od -An -v -tu1 "$tmp")" ||
    ! LC_ALL=C awk '{ for (i = 1; i <= NF; i++) if ($i != 10 && ($i < 32 || $i > 126)) bad = 1 } END { exit bad }' <<< "$byte_dump"; then
    PD_COUNT_DETAIL="ioclasscount rc=$rc raw=${display:-<empty>} (non-printable output)"
    rm -f "$tmp"
    return 1
  fi
  if [ "$rc" -eq 0 ]; then
    if parsed="$(LC_ALL=C awk '
      NR == 1 && /^AppleThunderboltRDMAProtectionDomain = [0-9]+$/ {
        held = $3
        valid = length(held) <= 4
        next
      }
      { valid = 0 }
      END { if (NR == 1 && valid) print held; else exit 1 }
    ' "$tmp")"; then
      PD_HELD="$parsed"
      rm -f "$tmp"
      return 0
    fi
  fi
  PD_COUNT_DETAIL="ioclasscount rc=$rc raw=${display:-<empty>}"
  rm -f "$tmp"
  return 1
}
