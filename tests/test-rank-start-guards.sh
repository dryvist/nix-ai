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
#   STUB — link_prep_ok / repair_link_prep / peer_rendezvous_listening /
#          set_wired_limit, because each is a thin wrapper over a macOS-only
#          binary (ifconfig, networksetup, nc, sysctl) that does not exist on the
#          Linux CI runner. Their own behaviour is verified on hardware:
#          `timeout 2 nc -z` returned rc 0 against a listener, rc 1 in 4 ms
#          against a closed port, and rc 124 at the bound against a blackhole
#          (macOS, 2026-07-25).
#   MIRROR — rank_start_tick below reproduces ONLY the watcher's elif skeleton,
#          because the watcher body also pings, calls launchctl and writes a
#          launchd state file at import time. The skeleton is 6 lines and the
#          decisions inside it are the real functions; keep it in step with
#          cluster-link-watcher.sh.
#
# Usage:
#   HELPERS=/path/to/cluster-link-helpers.sh \
#   GUARDS=/path/to/cluster-link-guards.sh bash test-rank-start-guards.sh
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

# Sourced in the module's concatenation order: halt_write lives in the helpers
# (the peer-liveness supervisor sets the same latch), halt_clear_accepted and the
# preconditions in the guards.
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to the path of cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to the path of cluster-link-guards.sh}"

# --- stubs for the macOS-only wrappers, plus call counters ------------------
link_ok=1
peer_listening=1
ceiling_ok=1
peer_probes=0
repairs=0

link_prep_ok() { [ "$link_ok" = 1 ]; }
repair_link_prep() {
  repairs=$((repairs + 1))
  return 1
}
peer_rendezvous_listening() {
  peer_probes=$((peer_probes + 1))
  [ "$peer_listening" = 1 ]
}
set_wired_limit() { [ "$ceiling_ok" = 1 ]; }

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
  rm -f "$halt_file" "$latch_file" "$kicks_file"
  link_ok=1
  peer_listening=1
  ceiling_ok=1
  peer_probes=0
  repairs=0
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
check "peer_rendezvous_listening true when the peer answers" 0 \
  "$(peer_rendezvous_listening && echo 0 || echo 1)"
peer_listening=0
check "peer_rendezvous_listening false when it does not" 1 \
  "$(peer_rendezvous_listening && echo 0 || echo 1)"
check "set_wired_limit true under the ceiling" 0 "$(set_wired_limit && echo 0 || echo 1)"
ceiling_ok=0
check "set_wired_limit false when the ceiling is refused" 1 \
  "$(set_wired_limit && echo 0 || echo 1)"
# repair_link_prep always reports failure (the stub models a repair that did not
# take), and must count the attempt. Called in this shell so the counter sticks.
reset_state
repair_link_prep || true
check "repair_link_prep reports failure" 1 "$(repair_link_prep > /dev/null 2>&1 && echo 0 || echo 1)"
check "repair_link_prep counted its attempt" 1 "$repairs"
reset_state

echo "peer not listening does NOT consume an attempt:"
# THE incident. Three attempts against an absent rank 0 = three leaked
# protection domains = a mandatory reboot. Waiting costs nothing.
reset_state
peer_listening=0
tick
check "start is skipped" skip "$VERDICT"
check "reason recorded" peer-rendezvous-absent "$PRECONDITION_REASON"
check "no attempt consumed" absent "$(kicks_now)"
tick
tick
check "still no attempts after three ticks" absent "$(kicks_now)"
check "and no halt" none "$(halt_cause)"
peer_listening=1
tick
check "coordinator appears -> the rank starts" start "$VERDICT"
check "now one attempt is counted" 1 "$(kicks_now)"

echo "the coordinator never waits on the worker (no mutual deadlock):"
reset_state
CLUSTER_ROLE=coordinator
peer_listening=0
tick
check "coordinator starts regardless" start "$VERDICT"
check "peer was never probed" 0 "$peer_probes"
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
check "peer probe never reached" 0 "$peer_probes"

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
peer_listening=0
tick
check "clear is rejected" re-halted "$VERDICT"
check "marker is back" manual-clear-rejected "$(halt_cause)"
check "no attempt consumed" 3 "$(kicks_now)"
grep -q 'still-failing=peer-rendezvous-absent' "$halt_file" ||
  { echo "  FAIL re-halt marker must name the still-failing precondition"; fail=1; }

echo "clearing the halt by hand is accepted once the cause is gone:"
rm -f "$halt_file"
peer_listening=1
tick
check "clear accepted, then the rank starts" start "$VERDICT"
check "attempt counter was reset by the accepted clear" 1 "$(kicks_now)"
check "latch cleared" missing "$([ -f "$latch_file" ] && echo latched || echo missing)"

exit "$fail"
