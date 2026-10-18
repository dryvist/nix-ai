#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/fake-pgrep" <<PGREP
#!$BASH
if [ "\${FAKE_PGREP_RC:-1}" -eq 0 ]; then
  printf '%s\\n' "\${FAKE_PGREP_OUTPUT:-4242}"
fi
exit "\${FAKE_PGREP_RC:-1}"
PGREP
chmod +x "$tmp/bin/fake-pgrep"

{
  printf '#!%s\n' "$BASH"
  cat <<'IBV'
printf 'hca_id: rdma_test\nmax_pd: %s\n' "${FAKE_MAX_PD:-11}"
IBV
} > "$tmp/bin/fake-ibv-devinfo"
chmod +x "$tmp/bin/fake-ibv-devinfo"

{
  printf '#!%s\n' "$BASH"
  cat <<'IOCLASSCOUNT'
case "$1" in
  AppleThunderboltRDMAProtectionDomain)
    printf '%s\n' "${FAKE_PD_OUTPUT:-AppleThunderboltRDMAProtectionDomain = 0}"
    exit "${FAKE_PD_RC:-0}"
    ;;
  AppleThunderboltRDMAQueuePair)
    printf '%s\n' "${FAKE_QP_OUTPUT:-AppleThunderboltRDMAQueuePair = 0}"
    exit "${FAKE_QP_RC:-0}"
    ;;
  IORDMAFamilyUC)
    printf '%s\n' "${FAKE_UC_OUTPUT:-IORDMAFamilyUC = 0}"
    exit "${FAKE_UC_RC:-0}"
    ;;
  *) exit 2 ;;
esac
IOCLASSCOUNT
} > "$tmp/bin/fake-ioclasscount"
chmod +x "$tmp/bin/fake-ioclasscount"

export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
export CLUSTER_RDMA_DEVICE=rdma_test
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_PD_RESERVE=5
export CLUSTER_PGREP_BIN="$tmp/bin/fake-pgrep"
export CLUSTER_IBV_DEVINFO_BIN="$tmp/bin/fake-ibv-devinfo"
export CLUSTER_IOCLASSCOUNT_BIN="$tmp/bin/fake-ioclasscount"

# shellcheck disable=SC1090
source "${STATUS:?set STATUS to cluster-rank-status.sh}"
# shellcheck disable=SC1090
source "${PD_COUNT:?set PD_COUNT to cluster-pd-count.sh}"
# shellcheck disable=SC1090
source "${PD_GATE:?set PD_GATE to cluster-pd-gate.sh}"

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
contains() {
  local label="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) echo "  ok   $label" ;;
    *)
      echo "  FAIL $label -> '$needle' not in: $hay"
      fail=1
      ;;
  esac
}
reset() {
  export CLUSTER_PD_DEVICE_BUDGET=11
  export CLUSTER_PD_RESERVE=5
  export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
  export CLUSTER_IOCLASSCOUNT_BIN="$tmp/bin/fake-ioclasscount"
  export FAKE_PGREP_RC=1
  export FAKE_PGREP_OUTPUT=4242
  export FAKE_MAX_PD=11
  export FAKE_PD_OUTPUT='AppleThunderboltRDMAProtectionDomain = 0'
  export FAKE_PD_RC=0
  export FAKE_QP_OUTPUT='AppleThunderboltRDMAQueuePair = 0'
  export FAKE_QP_RC=0
  export FAKE_UC_OUTPUT='IORDMAFamilyUC = 0'
  export FAKE_UC_RC=0
}
run_gate() {
  if pd_start_gate > "$tmp/gate.log" 2>&1; then
    GATE_RC=0
  else
    GATE_RC=$?
  fi
  GATE_LOG="$(cat "$tmp/gate.log")"
}
assert_gate() {
  local label="$1" want_rc="$2" want_reason="$3" want_held="$4" want_reboot="$5" verdict="$6" lines
  check "$label rc" "$want_rc" "$GATE_RC"
  check "$label reason" "$want_reason" "$PD_GATE_REASON"
  check "$label held" "$want_held" "$PD_HELD"
  check "$label reboot" "$want_reboot" "$PD_REBOOT"
  lines="$(grep -c '^cluster-join: pd-gate ' "$tmp/gate.log" || true)"
  check "$label writes one decision line" 1 "$lines"
  contains "$label logs decision" "cluster-join: pd-gate $verdict reason=$want_reason" "$GATE_LOG"
}

echo 'valid kernel counts and non-rank PD classes:'
reset
run_gate
assert_gate 'held=0 passes' 0 pd-reserve-available 0 0 PASS
contains 'zero count detail is logged' 'detail=no PDs held with no rank alive' "$GATE_LOG"

reset
export FAKE_QP_RC=2
export FAKE_UC_RC=2
run_gate
assert_gate 'unreadable informational classes do not refuse' 0 pd-reserve-available 0 0 PASS
contains 'queue-pair count is logged as information' 'class=AppleThunderboltRDMAQueuePair rc=2' "$GATE_LOG"
contains 'IORDMAFamilyUC count is logged as information' 'class=IORDMAFamilyUC rc=2' "$GATE_LOG"

reset
export FAKE_PD_OUTPUT='AppleThunderboltRDMAProtectionDomain = 3'
run_gate
assert_gate 'held=3 passes' 0 pd-reserve-available 3 0 PASS
contains 'nonzero count includes a warning' 'detail=WARN held=3 with no rank alive' "$GATE_LOG"

reset
export FAKE_PD_OUTPUT='AppleThunderboltRDMAProtectionDomain = 4'
run_gate
assert_gate 'held=4 still passes' 0 pd-reserve-available 4 0 PASS

echo 'rank and device probes fail closed:'
reset
export FAKE_PGREP_RC=0
export FAKE_PGREP_OUTPUT=$'4242\n4343'
run_gate
assert_gate 'rank alive refuses' 1 rank-alive '?' 0 REFUSE
contains 'rank refusal identifies pids' 'detail=pids=4242 4343' "$GATE_LOG"

reset
export FAKE_PGREP_RC=2
run_gate
assert_gate 'unanswerable rank probe refuses' 1 rank-probe-unanswerable '?' 0 REFUSE
contains 'rank probe refusal logs rc' 'detail=pgrep rc=2' "$GATE_LOG"

reset
unset CLUSTER_RANK_PROCESS_PATTERN
run_gate
assert_gate 'missing rank pattern refuses' 1 rank-probe-unanswerable '?' 0 REFUSE
contains 'missing rank pattern is logged' 'detail=CLUSTER_RANK_PROCESS_PATTERN is unset' "$GATE_LOG"

reset
export FAKE_MAX_PD=8
run_gate
assert_gate 'max_pd below budget refuses' 1 device-budget-unverified '?' 0 REFUSE
contains 'max_pd refusal logs measured detail' 'rdma_test reports max_pd=8' "$GATE_LOG"

reset
export FAKE_MAX_PD=unknown
run_gate
assert_gate 'unreadable max_pd refuses' 1 device-budget-unverified '?' 0 REFUSE
contains 'unreadable max_pd logs measured detail' 'did not report a readable max_pd' "$GATE_LOG"

reset
export FAKE_MAX_PD=12
run_gate
assert_gate 'max_pd above budget warns and passes' 0 pd-reserve-available 0 0 PASS
contains 'larger max_pd warning is logged' 'above the configured devicePdBudget=11' "$GATE_LOG"

echo 'invalid configuration refuses before probing:'
reset
unset CLUSTER_PD_DEVICE_BUDGET
run_gate
assert_gate 'missing budget refuses' 1 pd-gate-unconfigured '?' 0 REFUSE

reset
export CLUSTER_PD_DEVICE_BUDGET=eleven
run_gate
assert_gate 'non-integer budget refuses' 1 pd-gate-unconfigured '?' 0 REFUSE

reset
export CLUSTER_PD_DEVICE_BUDGET=0
run_gate
assert_gate 'budget zero refuses' 1 pd-gate-unconfigured '?' 0 REFUSE

reset
export CLUSTER_PD_DEVICE_BUDGET=$'eleven\n11'
run_gate
assert_gate 'multi-line budget refuses' 1 pd-gate-unconfigured '?' 0 REFUSE
contains 'multi-line budget remains one decision line' 'budget=eleven 11' "$GATE_LOG"

reset
unset CLUSTER_PD_RESERVE
run_gate
assert_gate 'missing reserve refuses' 1 pd-gate-unconfigured '?' 0 REFUSE

reset
export CLUSTER_PD_RESERVE=five
run_gate
assert_gate 'non-integer reserve refuses' 1 pd-gate-unconfigured '?' 0 REFUSE

reset
export CLUSTER_PD_RESERVE=0
run_gate
assert_gate 'reserve zero refuses' 1 pd-gate-unconfigured '?' 0 REFUSE

reset
export CLUSTER_PD_RESERVE=11
run_gate
assert_gate 'reserve equal to budget refuses' 1 pd-gate-unconfigured '?' 0 REFUSE

echo 'malformed kernel counts refuse and retain bounded evidence:'
reset
export CLUSTER_IOCLASSCOUNT_BIN="$tmp/bin/missing-ioclasscount"
run_gate
assert_gate 'missing ioclasscount refuses' 1 pd-count-unreadable '?' 0 REFUSE
contains 'missing binary rc is logged' 'ioclasscount rc=127' "$GATE_LOG"

reset
export FAKE_PD_OUTPUT='<no such class>'
run_gate
assert_gate 'unregistered class refuses' 1 pd-count-unreadable '?' 0 REFUSE
contains 'unregistered class raw output is logged' 'raw=<no such class>' "$GATE_LOG"

reset
export FAKE_PD_OUTPUT='AppleThunderboltRDMAProtectionDomain = unknown'
run_gate
assert_gate 'non-numeric count refuses' 1 pd-count-unreadable '?' 0 REFUSE

reset
export FAKE_PD_OUTPUT=$'AppleThunderboltRDMAProtectionDomain = 1\nAppleThunderboltRDMAProtectionDomain = 2'
run_gate
assert_gate 'multiple count lines refuse' 1 pd-count-unreadable '?' 0 REFUSE

reset
export FAKE_PD_OUTPUT=$'AppleThunderboltRDMAProtectionDomain = 1\n'
run_gate
assert_gate 'extra blank count line refuses' 1 pd-count-unreadable '?' 0 REFUSE

reset
export FAKE_PD_RC=1
run_gate
assert_gate 'nonzero count rc refuses' 1 pd-count-unreadable '?' 0 REFUSE
contains 'nonzero count rc is logged' 'ioclasscount rc=1' "$GATE_LOG"

reset
long_raw="$(printf '%0201d' 0)"
expected_raw="${long_raw:0:200}"
export FAKE_PD_OUTPUT="$long_raw"
run_gate
assert_gate 'long malformed count refuses' 1 pd-count-unreadable '?' 0 REFUSE
check 'count failure retains only the first 200 raw bytes' "$expected_raw" "${PD_COUNT_DETAIL#*raw=}"

echo 'reserve boundary refuses and asks for reboot:'
reset
export FAKE_PD_OUTPUT='AppleThunderboltRDMAProtectionDomain = 5'
run_gate
assert_gate 'held=5 reaches reserve' 1 pd-reserve 5 1 REFUSE

if [ "$fail" -ne 0 ]; then
  echo 'PD gate checks FAILED' >&2
  exit 1
fi
echo 'PD gate checks passed'
