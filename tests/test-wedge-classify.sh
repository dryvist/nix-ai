#!/usr/bin/env bash
# Unit test for wedge_classify (modules/mlx/scripts/wedge-detect.sh) — the
# pure two-condition discriminator between a llama-swap slot-accounting wedge
# and a genuinely saturated model. No mocks: the function takes only scalar
# args and does no I/O, so this sources the real shipped function directly.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/modules/mlx/scripts/wedge-detect.sh"

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

echo "both conditions hold -> suspect:"
check "fast 429 twice, flat engine steps" suspect "$(wedge_classify 429 4 429 3 100 100 500)"

echo "either condition alone is not enough:"
check "slow 429 (real queueing) clears despite flat steps" clear \
  "$(wedge_classify 429 4 429 600 100 100 500)"
check "fast 429 twice but engine actually stepped (genuinely busy) clears" clear \
  "$(wedge_classify 429 4 429 3 100 105 500)"

echo "a healthy response anywhere clears it:"
check "non-429 on either probe clears" clear "$(wedge_classify 200 4 429 3 100 100 500)"

echo "no guessing without a progress signal:"
check "both steps missing (mlx-lm backend, no metrics) is inconclusive" inconclusive \
  "$(wedge_classify 429 4 429 3 "" "" 500)"
check "one steps sample missing is inconclusive" inconclusive \
  "$(wedge_classify 429 4 429 3 100 "" 500)"

echo "boundary and transport-error handling:"
check "latency exactly at threshold is not 'under' it -> clear" clear \
  "$(wedge_classify 429 500 429 3 100 100 500)"
check "a transport error is not a 429 -> clear" clear \
  "$(wedge_classify error 4 429 3 100 100 500)"

exit "$fail"
