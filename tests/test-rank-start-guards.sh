#!/usr/bin/env bash
# Exercises the rank-start guards from modules/mlx/scripts/cluster-link-guards.sh
# — the preconditions that decide whether a rank start may happen at all, and
# whether it may consume one of the PD guard's countable attempts.
#
# Every case here is a 2026-07-24 incident replayed: a worker whose coordinator
# had no rank kickstarted three times into a rendezvous that did not exist,
# leaked three kernel RDMA protection domains (reboot-only), got correctly
# halted, and was then un-halted by hand — which burned the rest.
#
# WHAT IS REAL AND WHAT IS NOT, stated plainly:
#   REAL — rank_start_preconditions_ok, halt_write and halt_clear_accepted are
#          sourced from the shipped script and called as the watcher calls them.
#          This is the part the older tests/test-link-debounce.sh could not do.
#   STUB — link_prep_ok / repair_link_prep / set_wired_limit, because each is a
#          thin wrapper over a macOS-only binary (ifconfig, networksetup,
#          sysctl) absent on the Linux CI runner; plus date and sleep, so the
#          shared start boundary is asserted by the wait it COMPUTES rather than
#          by really sleeping through it.
#   MIRROR — rank_start_tick below reproduces ONLY the watcher's elif skeleton,
#          because the watcher body also pings, calls launchctl and writes a
#          launchd state file at import time. The skeleton is 6 lines and the
#          decisions inside it are the real functions; keep it in step with
#          cluster-link-watcher.sh.
#
# Usage:
#   BOOT_SCOPE=/path/to/cluster-boot-scope.sh \
#   LEDGER=/path/to/cluster-pd-ledger.sh \
#   HELPERS=/path/to/cluster-link-helpers.sh \
#   GUARDS=/path/to/cluster-link-guards.sh bash test-rank-start-guards.sh
#
# The RDMA protection-domain rungs the guards gained (ledger cap, reap-before-
# start) have their own file, tests/test-pd-debt.sh. Here they are configured
# inert — a real ledger path with no debt, and a reap stub that succeeds — so
# these cases keep testing what they were written to test.
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
kicks_file="$state_dir/rank-kickstarts"

export CLUSTER_ROLE=worker
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_RENDEZVOUS_PORT=11441
export CLUSTER_STATE_FILE="$state_dir/link-state"
# Rung 0 refuses outright when the PD guard is not wired up, so these must be
# present for any other rung to be reachable at all. That refusal is asserted in
# tests/test-pd-debt.sh; here the guard is simply configured and idle.
export CLUSTER_PD_DEBT_FILE="$state_dir/pd-debt"
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'

# Sourced in the module's concatenation order: current_boot_epoch in the boot
# scope, pd_debt_count in the ledger, halt_write in the helpers (the peer-liveness
# supervisor sets the same latch), halt_clear_accepted and the preconditions in
# the guards.
# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to the path of cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to the path of cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to the path of cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to the path of cluster-link-guards.sh}"

# --- stubs for the macOS-only wrappers, plus call counters ------------------
link_ok=1
ceiling_ok=1
repairs=0
# Clock and sleep are stubbed so the shared-start-boundary barrier is asserted by
# the wait it COMPUTES, not by really sleeping. Only `date +%s` is intercepted;
# anything else defers to the real binary so helpers that timestamp still work.
align_now=0
slept=0

link_prep_ok() { [ "$link_ok" = 1 ]; }
# The peer rung. Stubbed rather than driven through CLUSTER_PING_BIN because the
# cases below care only about the VERDICT each answer produces; that the real
# probe is a ping of CLUSTER_STATIC_PEER_IP is pinned by the stub contract
# assertions, same as link_prep_ok.
peer_ok=1
peer_reachable() { [ "$peer_ok" = 1 ]; }
repair_link_prep() {
  repairs=$((repairs + 1))
  return 1
}
set_wired_limit() { [ "$ceiling_ok" = 1 ]; }
# The reap-before-start rung. Stubbed to "no survivor" here; the real function
# and its fail-closed behaviour are exercised in tests/test-pd-debt.sh, which
# drives it through the CLUSTER_PGREP_BIN / CLUSTER_KILL_BIN seams.
reap_ok=1
rank_reap_verified() { [ "$reap_ok" = 1 ]; }
# The generation-parity rung (RULE 2), stubbed healthy here; its refuse/pass
# matrix and the drift heal are exercised in tests/test-generation-heal.sh.
generation_parity_cached() { printf 'state=ok local=aaaa deploy=aaaa'; }
date() {
  case "$1" in
    +%s) echo "$align_now" ;;
    *) command date "$@" ;;
  esac
}
sleep() { slept="$1"; }

# --- the watcher's rank-start branch skeleton (MIRROR — see header) ---------
# The verdict lands in VERDICT rather than on stdout, and the guards' own log
# lines go to $log: a command substitution would run the tick in a subshell,
# where PRECONDITION_REASON and the stub counters could not be observed.
log="$state_dir/tick.log"
rank_start_tick() {
  local kicks=0
  VERDICT=""
  if [ -f "$halt_file" ]; then
    VERDICT=halted
    return 0
  fi
  if [ -f "$latch_file" ] && ! halt_clear_accepted "$halt_file" "$latch_file" "$kicks_file"; then
    VERDICT=re-halted
    return 0
  fi
  [ -f "$kicks_file" ] && kicks="$(cat "$kicks_file")"
  if [ "$kicks" -ge "${CLUSTER_MAX_KICKSTARTS:-3}" ]; then
    halt_write "$halt_file" "$latch_file" rank-start-failures \
      "$kicks consecutive failed rank starts"
    VERDICT=halt
    return 0
  fi
  if ! rank_start_preconditions_ok; then
    VERDICT=skip
    return 0
  fi
  printf '%s\n' "$((kicks + 1))" > "$kicks_file"
  VERDICT=start
}

# One tick with the guards' log captured. Never called through a command
# substitution — VERDICT and the stub counters must survive the call.
tick() { rank_start_tick >> "$log" 2>&1; }

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
reset_state() {
  rm -f "$halt_file" "$latch_file" "$kicks_file" "$CLUSTER_PD_DEBT_FILE"
  link_ok=1
  peer_ok=1
  ceiling_ok=1
  reap_ok=1
  repairs=0
  slept=0
  align_now=0
  unset CLUSTER_RANK_START_ALIGN_SECS
}
kicks_now() { cat "$kicks_file" 2> /dev/null || echo absent; }
halt_cause() { sed -n 's/.*cause=\([^	]*\).*/\1/p' "$halt_file" 2> /dev/null || echo none; }

echo "stub contracts (the guards call these indirectly, so pin them here):"
# Every case below reaches the stubs only through rank_start_preconditions_ok,
# which is sourced. Asserting them directly does two jobs: it proves the stubs
# honour the contract the real macOS wrappers have, and it keeps the indirection
# from reading as dead code to a static analyser.
reset_state
check "link_prep_ok true when the link is up" 0 "$(link_prep_ok && echo 0 || echo 1)"
link_ok=0
check "link_prep_ok false when the link is down" 1 "$(link_prep_ok && echo 0 || echo 1)"
check "peer_reachable true when the peer answers" 0 "$(peer_reachable && echo 0 || echo 1)"
peer_ok=0
check "peer_reachable false when the peer is absent" 1 "$(peer_reachable && echo 0 || echo 1)"
peer_ok=1
check "set_wired_limit true under the ceiling" 0 "$(set_wired_limit && echo 0 || echo 1)"
ceiling_ok=0
check "set_wired_limit false when the ceiling is refused" 1 \
  "$(set_wired_limit && echo 0 || echo 1)"
align_now=4242
check "date +%s returns the stubbed clock" 4242 "$(date +%s)"
check "date passes other formats to the real binary" ok \
  "$(date -u +%Y > /dev/null && echo ok || echo broken)"
sleep 7
check "sleep records instead of sleeping" 7 "$slept"
# repair_link_prep always reports failure (the stub models a repair that did not
# take), and must count the attempt. Called in this shell so the counter sticks.
reset_state
repair_link_prep || true
check "repair_link_prep reports failure" 1 "$(repair_link_prep > /dev/null 2>&1 && echo 0 || echo 1)"
check "repair_link_prep counted its attempt" 1 "$repairs"
reset_state

echo "both ranks hold for the shared start boundary:"
# The worker used to wait for rank 0 to be listening. That GUARANTEED it reached
# distributed init ~20-30s after the coordinator — far outside jaccl's fixed
# ~15s connect budget — so the coordinator had already exited and the worker
# dialled a dead port (errno 60). Measured 2026-07-25: sequential starts
# oscillate and both ranks die; starting together holds and serves. There is no
# leader to wait for now, only a boundary both hosts compute identically.
reset_state
export CLUSTER_RANK_START_ALIGN_SECS=60
align_now=100 # 40s past a boundary, so 20s remain
tick
check "start still proceeds" start "$VERDICT"
check "waited exactly to the next boundary" 20 "$slept"
check "attempt consumed once started" 1 "$(kicks_now)"

reset_state
export CLUSTER_RANK_START_ALIGN_SECS=60
align_now=120 # already exactly on a boundary
tick
check "no wait when already on the boundary" 0 "$slept"
check "start proceeds" start "$VERDICT"

reset_state
export CLUSTER_RANK_START_ALIGN_SECS=0
align_now=100
tick
check "alignment disabled means no wait" 0 "$slept"
check "start proceeds" start "$VERDICT"
reset_state

echo "both roles observe the SAME boundary (alignment, not ordering):"
# The point of the boundary is that neither rank leads. Feed the coordinator the
# identical clock the worker saw above and it must compute the identical wait —
# that is what puts the two inside jaccl's connect budget together.
reset_state
CLUSTER_ROLE=coordinator
export CLUSTER_RANK_START_ALIGN_SECS=60
align_now=100
tick
check "coordinator starts too" start "$VERDICT"
check "coordinator waits the same 20s the worker did" 20 "$slept"
CLUSTER_ROLE=worker

echo "missing local link address blocks the start:"
# errno 49 EADDRNOTAVAIL — a boot can leave carrier up with no address at all.
reset_state
link_ok=0
tick
check "start is blocked" skip "$VERDICT"
check "reason recorded" link-address-missing "$PRECONDITION_REASON"
check "no attempt consumed" absent "$(kicks_now)"
check "repair was attempted" 1 "$repairs"

echo "an absent peer blocks the start and costs nothing:"
# THE MOST AVOIDABLE PD LEAK. A rank started against a host that is not there
# still reaches distributed init, still allocates a protection domain, and still
# dies with errno 60 when jaccl's connect budget runs out — a certain failure
# billed to a boot-scoped, reboot-only resource. Three pings prevent it.
reset_state
peer_ok=0
tick
check "start is blocked" skip "$VERDICT"
check "reason recorded" peer-unreachable "$PRECONDITION_REASON"
check "no attempt consumed" absent "$(kicks_now)"

echo "the peer rung runs BEFORE the alignment hold:"
# A dead peer must cost neither a domain nor a wait. If this rung ran after the
# hold, every tick against an absent peer would burn up to a full alignment
# period before refusing — and re-probing after the hold would spend part of the
# ~15s connect budget the hold exists to protect.
reset_state
peer_ok=0
export CLUSTER_RANK_START_ALIGN_SECS=60
align_now=100 # 40s past a boundary: 20s would be slept if the rung came later
tick
check "start is blocked" skip "$VERDICT"
check "no time slept on a dead peer" 0 "$slept"
unset CLUSTER_RANK_START_ALIGN_SECS

echo "a peer that comes back unblocks the start:"
# The rung must be a hold, not a halt: no marker, no latch, no consumed attempt,
# so the next tick after the peer returns simply proceeds.
reset_state
peer_ok=0
tick
check "blocked while absent" skip "$VERDICT"
check "no halt marker written" missing "$([ -f "$halt_file" ] && echo latched || echo missing)"
peer_ok=1
tick
check "starts once the peer answers" start "$VERDICT"
check "first attempt consumed only now" 1 "$(kicks_now)"

echo "repair is overridable but the block is not:"
reset_state
link_ok=0
export CLUSTER_LINK_REPAIR=0
tick
check "start still blocked" skip "$VERDICT"
check "repair skipped" 0 "$repairs"
export CLUSTER_LINK_REPAIR=1

echo "wired ceiling still gates the start without consuming an attempt:"
reset_state
ceiling_ok=0
tick
check "start is blocked" skip "$VERDICT"
check "reason recorded" wired-ceiling "$PRECONDITION_REASON"
check "no attempt consumed" absent "$(kicks_now)"

echo "the halt records WHY:"
reset_state
printf '3\n' > "$kicks_file"
tick
check "cap reached -> halt" halt "$VERDICT"
check "cause is in the marker" rank-start-failures "$(halt_cause)"
check "latch written" latched "$([ -f "$latch_file" ] && echo latched || echo missing)"
tick
check "halted ticks do nothing" halted "$VERDICT"

echo "clearing the halt by hand re-verifies the cause (rejected):"
# What actually happened: a human deleted the marker on an unverified hypothesis
# and burned the remaining protection domains.
rm -f "$halt_file"
link_ok=0
tick
check "clear is rejected" re-halted "$VERDICT"
check "marker is back" manual-clear-rejected "$(halt_cause)"
check "no attempt consumed" 3 "$(kicks_now)"
grep -q 'still-failing=link-address-missing' "$halt_file" ||
  { echo "  FAIL re-halt marker must name the still-failing precondition"; fail=1; }

echo "clearing the halt by hand is accepted once the cause is gone:"
rm -f "$halt_file"
link_ok=1
tick
check "clear accepted, then the rank starts" start "$VERDICT"
check "attempt counter was reset by the accepted clear" 1 "$(kicks_now)"
check "latch cleared" missing "$([ -f "$latch_file" ] && echo latched || echo missing)"

# Boot scoping of the halt marker lives in tests/test-halt-boot-scope.sh
# (split out at the 12KB file cap); it unit-tests the halt helpers directly.

exit "$fail"
