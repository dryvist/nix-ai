#!/usr/bin/env bash
# Exercises the runtime wired-ceiling guard (rank_wired_ceiling_ok in
# modules/mlx/scripts/cluster-link-guards.sh) — the only guard in that file that
# judges a rank ALREADY RUNNING.
#
# WHY THIS EXISTS. On 2026-08-01 this host hard-reset. A cluster rank started
# legally — every rung in rank_start_preconditions_ok ran and passed — and wired
# then climbed to 96.7 GiB against a 100 GiB iogpu.wired_limit_mb. WindowServer
# asked Metal for a command buffer, got nothing, and blocked inside the GPU
# driver (IOGPUFamily then AGXG16X) for 80 seconds; watchdogd killed it and the
# hardware watchdog reset the machine, recording boot fault "wdog,reset_in_1".
# Every existing guard stayed green throughout, because every existing guard is
# a START precondition and had already run. This file is the test that fails if
# the runtime rung regresses back into that blind spot.
#
# THE PROPERTY MOST WORTH PROTECTING is the fail-OPEN behaviour on an unreadable
# probe (section 4). mem_headroom_ok deliberately fails CLOSED — refusing to
# start costs nothing. This rung REAPS, so the same choice would tear down a
# healthy serving rank whenever vm_stat hiccups. A "consistency" cleanup that
# aligns the two is a regression, not a tidy-up, and section 4 must fail loudly.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — mem_stat_mb and rank_wired_ceiling_ok are sourced from the shipped
#           script and called as the watcher calls them.
#   STUB  — vm_stat, as a generated executable (not a shell function) on
#           CLUSTER_VMSTAT_BIN, for the same reason test-mem-headroom.sh
#           generates it: the shipped code invokes it through a variable
#           holding a path, so a function would not exercise the same call.
#
# Usage:
#   BOOT_SCOPE=… LEDGER=… HELPERS=… GUARDS=… bash test-rank-wired-ceiling.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

export CLUSTER_ROLE=worker
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_RENDEZVOUS_PORT=11441
export CLUSTER_STATE_FILE="$state_dir/link-state"
export CLUSTER_PD_DEBT_FILE="$state_dir/pd-debt"
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'

# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to cluster-link-guards.sh}"

# --- vm_stat stub, generated executable (see header for why not a function) --
bin="$state_dir/bin"
mkdir -p "$bin"
vmstat_fixture="$state_dir/vmstat-output"
vmstat_rc="$state_dir/vmstat-rc"
cat > "$bin/vm_stat" << VMSTAT
#!$BASH
forced="\$(cat '$vmstat_rc' 2>/dev/null || true)"
if [ -n "\$forced" ]; then exit "\$forced"; fi
cat '$vmstat_fixture'
VMSTAT
chmod +x "$bin/vm_stat"
export CLUSTER_VMSTAT_BIN="$bin/vm_stat"

# Field order and the trailing "." on every count mirror real vm_stat output.
write_vmstat() {
  local page_size="$1" free="$2" wired="$3"
  cat > "$vmstat_fixture" << EOF
Mach Virtual Memory Statistics: (page size of ${page_size} bytes)
Pages free:                              ${free}.
Pages active:                            1000.
Pages inactive:                          0.
Pages speculative:                       0.
Pages throttled:                         0.
Pages wired down:                        ${wired}.
Pages purgeable:                         0.
"Translation faults":                    123456.
Pages copy-on-write:                     0.
Pages zero filled:                       0.
Pages reactivated:                       0.
Pages purged:                            0.
File-backed pages:                       0.
Anonymous pages:                         0.
Pages stored in compressor:              0.
Pages occupied by compressor:            0.
Decompressions:                          0.
Compressions:                            0.
Pageins:                                 0.
Pageouts:                                0.
Swapins:                                 0.
Swapouts:                                0.
EOF
}

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
# 0 = the rank may keep running, 1 = reap it. The breach detail goes to stdout,
# so the verdict discards it here and section 2 captures it separately.
verdict() { rank_wired_ceiling_ok "$1" > /dev/null && echo keep || echo reap; }
# The detail is the function's stdout on breach, empty otherwise.
detail_of() { rank_wired_ceiling_ok "$1" || true; }
reset_state() {
  rm -f "$vmstat_rc"
  write_vmstat 16384 0 0
}

echo "0. the guard is disabled with 0/unset, whatever vm_stat says:"
reset_state
write_vmstat 16384 0 6553600 # 100 GiB wired — would reap at any live ceiling
check "0 disables the guard" keep "$(verdict 0)"
check "empty disables the guard" keep "$(verdict '')"
check "a non-numeric ceiling disables it rather than guessing" keep "$(verdict abc)"

echo "1. BOTH measured healthy shapes are left alone:"
# A healthy serving rank wires approximately its whole shard — 3271199 pages
# (~49.9 GiB) with both ranks serving, corroborated within 2.3% by the
# REALVMSTAT capture in test-mem-headroom.sh. An earlier ~3.5 GiB claim was
# retracted as a bad measurement, but the low-wired case is asserted anyway:
# it is the pre-load state every rank passes through on the way up, and
# reaping there would kill a rank that is still loading its shard.
reset_state
write_vmstat 16384 3276800 229376 # 3.5 GiB wired — the smaller measurement
check "healthy rank, smaller measurement, is not reaped" keep "$(verdict 76800)"
write_vmstat 16384 1048576 3271199 # the larger measurement, verbatim page count
check "healthy rank, larger measurement, is not reaped" keep "$(verdict 76800)"

echo "2. wired at or above the ceiling reaps:"
reset_state
# 16384-byte pages: MB * 64 = pages. 96768MB * 64 = 6193152; 1024MB * 64 = 65536.
write_vmstat 16384 65536 6193152 # 1 GiB free, 96768MB (~94.5 GiB) wired: the incident
check "the incident shape is reaped" reap "$(verdict 76800)"
check "exactly at the ceiling reaps (>= not >)" reap "$(verdict 96768)"
check "one MB above the incident value keeps" keep "$(verdict 96770)"

echo "   ...and the detail names both numbers, for the page:"
breach_detail="$(detail_of 76800)"
check "detail states the wired figure" yes \
  "$(case "$breach_detail" in *"96768MB wired"*) echo yes ;; *) echo no ;; esac)"
check "detail states the ceiling it crossed" yes \
  "$(case "$breach_detail" in *"76800MB runtime ceiling"*) echo yes ;; *) echo no ;; esac)"
check "a passing check prints nothing at all" "" "$(detail_of 96770)"

echo "3. page size is READ from vm_stat, never assumed 16384:"
# At a hardcoded 16384 this reads as 1024MB and would NOT reap against a
# 2000MB ceiling; the real page size (65536, 4x larger) makes it 4096MB.
reset_state
write_vmstat 65536 0 65536
check "the real (non-16384) page size decides the verdict" reap "$(verdict 2000)"

echo "4. an unreadable vm_stat FAILS OPEN — a healthy rank is never reaped on a blind probe:"
# THE ASYMMETRY THAT MUST NOT BE "TIDIED UP". mem_headroom_ok fails CLOSED on
# the same condition, and that is correct there: refusing to START costs
# nothing, since nothing is running. Here the cost is a live generation plus a
# fresh distributed init, which leaks a protection domain whenever it races. A
# missed tick costs one interval. Aligning the two directions is a regression.
reset_state
printf '1\n' > "$vmstat_rc"
check "unreadable probe does NOT reap" keep "$(verdict 1)"
rm -f "$vmstat_rc"

echo "5. the guard reads wired, not free (the rung above reads free):"
# Sharing mem_stat_mb makes a column mix-up cheap and silent, and the two
# numbers move in opposite directions: the incident had wired HIGH and free
# LOW. Plenty free with wired over the ceiling must still reap.
reset_state
write_vmstat 16384 6553600 5242880 # 100 GiB free, 80 GiB wired
check "high free does not excuse wired over the ceiling" reap "$(verdict 76800)"
write_vmstat 16384 65536 65536 # 1 GiB free, 1 GiB wired
check "low free alone does not reap (that is mem_headroom_ok's job)" keep "$(verdict 76800)"

exit "$fail"
