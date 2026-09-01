#!/usr/bin/env bash
# Unit test for stuck_busy_action (modules/mlx/scripts/stuck-busy-streak.sh) —
# the rule that decides whether the metrics-free wedge streak accrues or
# clears on a given tick. No mocks: the function takes only scalar args and
# does no I/O, so this sources the real shipped function directly.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/modules/mlx/scripts/stuck-busy-streak.sh"

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

echo "only a busy model WITH a healthy control accrues:"
check "busy + healthy sibling" accrue "$(stuck_busy_action yes yes)"

echo "a recovered model clears (no stale count can page later):"
check "not busy + healthy sibling" clear "$(stuck_busy_action no yes)"

# The regression this file exists for. Before the fix this tick matched
# neither the accrual branch nor the clear branch, so the streak FROZE: a
# partial streak survived an arbitrarily long saturation gap and then paged
# (and unloaded) claiming those checks had been consecutive.
echo "busy with NO control clears rather than holding:"
check "busy + no healthy sibling" clear "$(stuck_busy_action yes no)"

echo "neither condition clears:"
check "not busy + no healthy sibling" clear "$(stuck_busy_action no no)"

echo "anything that is not an explicit yes is not a yes:"
check "empty args" clear "$(stuck_busy_action '' '')"
check "missing args" clear "$(stuck_busy_action)"
check "busy spelled otherwise" clear "$(stuck_busy_action true yes)"

exit "$fail"
