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
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
down_strikes_file="$state_dir/link-down-strikes"

# probe: 0 = peer replied, 1 = no reply.
tick() {
  local prev="$1" probe="$2" cur
  if [ "$probe" -eq 0 ]; then
    cur="up"
    rm -f "$down_strikes_file"
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
  fi
  printf '%s' "$cur"
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

exit "$fail"
