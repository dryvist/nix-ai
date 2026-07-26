#!/usr/bin/env bash
# Boot scoping of the rank halt marker — a unit test of the halt helpers, split
# out of tests/test-rank-start-guards.sh when that file passed the 12KB cap.
#
# Why this behaviour exists: every cause a halt can record is process or kernel
# state — exhausted RDMA protection domains, a wedged rank, a precondition that
# was failing at the time. None of it survives a reboot, and this repo's doctrine
# is that PD exhaustion is reboot-only to clear. But the marker and its latch
# outlived the machine, so after a reboot the watcher took the halted branch
# forever and a cold boot could never form the cluster. It went unnoticed because
# every test and hand-run drill cleared the marker first, which quietly made
# unattended formation untested.
#
# REAL — halt_write, halt_drop_if_pre_boot and current_boot_epoch are sourced from
#        the shipped helpers and called exactly as the watcher calls them.
# STUB — sysctl only, because the Linux CI runner has no kern.boottime. Stubbing
#        it also lets a reboot be simulated exactly, by changing the reported boot
#        between writing the halt and evaluating it.
#
# Usage:
#   HELPERS=/path/to/cluster-link-helpers.sh bash test-halt-boot-scope.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
kicks_file="$state_dir/rank-kickstarts"

export CLUSTER_STATE_FILE="$state_dir/link-state"

# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to the path of cluster-link-helpers.sh}"

boot_now=1785031601
sysctl() { echo "{ sec = $boot_now, usec = 233215 } Sat Jul 25 22:06:41 2026"; }

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  ok   $label -> $got"
  else
    echo "  FAIL $label -> got '$got', want '$want'"
    fail=1
  fi
}
recorded_boot() {
  awk -F'\t' '{for (i = 1; i <= NF; i++) if ($i ~ /^boot=/) { sub(/^boot=/, "", $i); print $i; exit }}' \
    "$halt_file" 2> /dev/null
}
marker() { [ -f "$halt_file" ] && echo latched || echo missing; }
latch() { [ -f "$latch_file" ] && echo latched || echo missing; }
reset_state() { rm -f "$halt_file" "$latch_file" "$kicks_file"; }

echo "the boot epoch is parsed from sec, never usec:"
# An unanchored `.*sec = ` matches through "usec = " and captures the
# MICROSECONDS — a value so small nothing is ever older than it, which silently
# disables every check built on this. The stub is asserted directly so the
# indirection does not read as dead code to a static analyser.
check "sysctl stub reports a boottime line" 1785031601 \
  "$(sysctl -n kern.boottime | sed -n 's/^{ *sec *= *\([0-9]*\).*/\1/p')"
check "current_boot_epoch returns sec, not usec" 1785031601 "$(current_boot_epoch)"

echo "halt_write records the boot it was written under:"
reset_state
halt_write "$halt_file" "$latch_file" rank-start-failures "3 consecutive failed rank starts"
check "marker written" latched "$(marker)"
check "boot field recorded" 1785031601 "$(recorded_boot)"

echo "a halt from a PREVIOUS boot is dropped:"
boot_now=1785099999 # simulate a reboot
halt_drop_if_pre_boot "$halt_file" "$latch_file" "$kicks_file" > /dev/null
check "marker dropped" missing "$(marker)"
check "latch dropped too" missing "$(latch)"

echo "a halt from THIS boot still stands (PD guard not weakened):"
reset_state
halt_write "$halt_file" "$latch_file" rank-start-failures "3 consecutive failed rank starts"
halt_drop_if_pre_boot "$halt_file" "$latch_file" "$kicks_file" > /dev/null
check "marker kept" latched "$(marker)"
check "latch kept" latched "$(latch)"

echo "an unreadable boot time FAILS CLOSED:"
# The deployed watcher could not read sysctl at all: /usr/sbin is not on a
# writeShellApplication's PATH. halt_write then recorded boot='unknown' and every
# halt was dropped on every tick, disabling the PD guard. Whatever the cause, an
# unknown boot must never drop a halt.
reset_state
halt_write "$halt_file" "$latch_file" rank-start-failures "3 consecutive failed rank starts"
sysctl() { :; } # unreachable / no output
check "sysctl stub yields nothing" "" "$(sysctl -n kern.boottime)"
check "boot epoch empty" "" "$(current_boot_epoch)"
halt_drop_if_pre_boot "$halt_file" "$latch_file" "$kicks_file" > /dev/null
check "halt KEPT when the boot time is unknown" latched "$(marker)"
sysctl() { echo "{ sec = $boot_now, usec = 233215 } Sat Jul 25 22:06:41 2026"; }
check "sysctl stub restored" "$boot_now" \
  "$(sysctl -n kern.boottime | sed -n 's/^{ *sec *= *\([0-9]*\).*/\1/p')"

echo "operator prose cannot spoof the boot field:"
# The detail text is operator-facing. A greedy regex would let it decide whether
# the halt survives, so the field is extracted tab-exactly.
reset_state
boot_now=1785031601 # written under THIS boot...
halt_write "$halt_file" "$latch_file" rank-start-failures \
  "peer said boot=1785099999 which must not be believed"
boot_now=1785099999 # ...then the machine reboots to the value the prose claims
halt_drop_if_pre_boot "$halt_file" "$latch_file" "$kicks_file" > /dev/null
check "dropped on the real field despite matching prose" missing "$(marker)"

exit "$fail"
