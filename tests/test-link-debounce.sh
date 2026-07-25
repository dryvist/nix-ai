#!/usr/bin/env bash
# Exercises the link-probe debounce state machine from
# modules/mlx/scripts/cluster-link-watcher.sh, driving it through the
# sequences that matter and asserting the resulting link state — so the
# asymmetry (up believed instantly, down earned over N strikes) is checked
# rather than eyeballed.
#
# LIMITATION, stated plainly: this MIRRORS the watcher's logic instead of
# sourcing it, because the probe block is inline in a script that also calls
# launchctl, sysctl and curl at import time. So it proves the logic is right;
# it does NOT protect against the watcher drifting away from this copy. That
# is the same certify-by-proxy weakness this repo keeps finding elsewhere, and
# it should be closed by sourcing the real block once the checks harness from
# the alert-payload work is available to wire it into.
#
# The threshold this file exercises is no longer a bare number in the script: it
# is derived in modules/mlx/cluster-watcher-env.nix from
# clusterMode.linkDownSettleSecs and clusterMode.tickIntervalSecs (seconds, the
# unit an operator actually thinks in), so the settle window and the tick cannot
# drift apart. That derivation is pinned by lib/checks/mlx-cluster.nix; what
# follows pins the state machine the derived value feeds.
#
# tests/test-rank-start-guards.sh covers the other half of the same state
# machine — the preconditions that gate a rank START — and sources the real
# functions rather than mirroring them.
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
down_strikes_file="$state_dir/link-down-strikes"
down_quiet_file="$state_dir/link-down-quiet-ticks"
# Every line the already-down branch would emit, so the reporting cadence can be
# asserted rather than eyeballed.
report_log="$state_dir/reports"
: > "$report_log"

# probe: 0 = peer replied, 1 = no reply.
tick() {
  local prev="$1" probe="$2" cur
  if [ "$probe" -eq 0 ]; then
    cur="up"
    rm -f "$down_strikes_file" "$down_quiet_file"
  elif [ "$prev" = "up" ]; then
    local strikes=0
    [ -f "$down_strikes_file" ] && strikes="$(cat "$down_strikes_file")"
    strikes=$((strikes + 1))
    printf '%s\n' "$strikes" > "$down_strikes_file"
    if [ "$strikes" -ge "${CLUSTER_LINK_DOWN_STRIKES:-2}" ]; then
      cur="down"
      rm -f "$down_strikes_file"
    else
      cur="up"
    fi
  else
    cur="down"
    local downs=0
    [ -f "$down_quiet_file" ] && downs="$(cat "$down_quiet_file")"
    downs=$((downs + 1))
    printf '%s\n' "$downs" > "$down_quiet_file"
    if [ "$downs" -eq 1 ] \
      || [ "$((downs % ${CLUSTER_DOWN_REPORT_EVERY:-20}))" -eq 0 ]; then
      printf 'report@%s\n' "$downs" >> "$report_log"
    fi
  fi
  printf '%s' "$cur"
}
reports() { wc -l < "$report_log" | tr -d ' '; }

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

echo "default threshold (2):"
# The regression this guards: ONE dropped packet used to declare the link
# down, which tore the rank down and deleted rank-halted + rank-kickstarts,
# resetting the RDMA PD guard. A flapping link could therefore never
# accumulate toward the halt.
check "single dropped packet holds up" up "$(tick up 1)"
check "second consecutive failure declares down" down "$(tick up 1)"
check "staying down stays down" down "$(tick down 1)"
check "reply from down comes straight up" up "$(tick down 0)"

# A reply must clear the count, or unrelated single losses spread over hours
# would eventually accumulate into a spurious teardown.
echo "strike counter resets on any reply:"
_=$(tick up 1)
_=$(tick up 0)
check "strike cleared, so next single loss holds up" up "$(tick up 1)"

echo "threshold is configurable:"
CLUSTER_LINK_DOWN_STRIKES=3
rm -f "$down_strikes_file"
check "1/3 holds" up "$(tick up 1)"
check "2/3 holds" up "$(tick up 1)"
check "3/3 declares down" down "$(tick up 1)"

echo "a still-failing probe stays audible while down (and does not spam):"
# The regression this guards: this branch used to emit NOTHING, so a probe that
# could never succeed was indistinguishable from an idle, correctly-down link.
# On 2026-07-25 that hid a denied macOS Local Network permission for 65 minutes
# while launchctl reported runs=115, last exit code=0.
CLUSTER_LINK_DOWN_STRIKES=2
CLUSTER_DOWN_REPORT_EVERY=5
rm -f "$down_strikes_file" "$down_quiet_file"
: > "$report_log"
_=$(tick down 1)
check "first confirmed-down tick reports" 1 "$(reports)"
for _ in 1 2 3; do _=$(tick down 1); done
check "ticks 2-4 stay quiet" 1 "$(reports)"
_=$(tick down 1)
check "tick 5 reports on the cadence" 2 "$(reports)"
for _ in 1 2 3 4; do _=$(tick down 1); done
check "ticks 6-9 stay quiet" 2 "$(reports)"
_=$(tick down 1)
check "tick 10 reports again" 3 "$(reports)"
# A recovered link must reset the cadence, so the next outage reports promptly
# instead of inheriting a mid-cycle counter.
_=$(tick down 0)
: > "$report_log"
_=$(tick down 1)
check "recovery resets the counter, so the next down reports at once" 1 "$(reports)"

exit "$fail"
