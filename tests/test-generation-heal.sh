#!/usr/bin/env bash
# THE CHECK THAT FAILS IF GENERATION PARITY STOPS BEING A HARD, SELF-HEALING GATE.
#
# RULE 2 (operator, verbatim): "make sure the actual, automated, non-AI steps
# enforce the nix generations to march exactly on both / all devices before
# continuing with other setup automated steps." The 86-hour outage was a node
# off the deployed generation; PR #1477 put DETECTION on the watcher's clock
# but left the HEAL in cluster-join (human-initiated) and left rank starts
# ungated — a drifted pair could still quiesce serving and assemble a
# mixed-stack rank (the INC-17070 config-parity variable).
#
# Properties, all against the REAL shipped functions:
#   1. rank_start_preconditions_ok REFUSES on drift and unstamped (no attempt
#      consumed), passes on ok / unverified / disabled;
#   2. a by-hand halt clear during drift is REJECTED and re-halts naming
#      generation-parity;
#   3. the heal is DETACHED (a transient launchd job the watcher submits, so
#      the rebuild survives its own activation booting the watcher out),
#      BOUNDED per distinct deploy revision, single-flight, and never touches
#      a machine whose rank is serving;
#   4. a finished heal invalidates the parity cache, so success is judged by
#      re-reading the truth rather than trusting the job.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — rank_start_preconditions_ok, halt_clear_accepted, halt_write,
#           generation_parity_cached / generation_parity_fact,
#           generation_heal_maybe, rank_process_running, pd_debt_count.
#   STUB  — link_prep_ok / peer_reachable / set_wired_limit /
#           rank_reap_verified / repair_link_prep / sysctl / hostname / alert
#           (macOS-only or externally-observable), launchctl through the
#           CLUSTER_LAUNCHCTL_BIN seam, pgrep through CLUSTER_PGREP_BIN, and
#           the two parity leaf readers.
#   PIN   — call sites and ORDER in cluster-link-watcher.sh (parity first,
#           before the link probe), cluster-link-guards.sh (parity rung before
#           every setup rung) and cluster-script-layers.nix (the heal layer is
#           actually shipped in the watcher).
#
# Usage:
#   BOOT_SCOPE=... LEDGER=... HELPERS=... PARITY=... FACTS=... STATUS=... \
#   HEAL=... GUARDS=... WATCHER=... LAYERS=... bash test-generation-heal.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
kicks_file="$state_dir/rank-kickstarts"
attempts_file="$state_dir/generation-heal-attempts"
gen_parity_file="$state_dir/generation-parity"
pages="$state_dir/pages"
lc_log="$state_dir/launchctl-calls"
: > "$pages"
: > "$lc_log"

export CLUSTER_ROLE=worker
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_RENDEZVOUS_PORT=11441
export CLUSTER_STATE_FILE="$state_dir/link-state"
export CLUSTER_PD_DEBT_FILE="$state_dir/pd-debt"
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
export CLUSTER_GENERATION_REPO=example/deploy
export CLUSTER_GENERATION_HEAL_LABEL=dev.mlx-cluster.generation-heal
export CLUSTER_GENERATION_HEAL_MAX=2

# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${PARITY:?set PARITY to cluster-generation-parity.sh}"
# shellcheck disable=SC1090
source "${FACTS:?set FACTS to cluster-link-facts.sh}"
# shellcheck disable=SC1090
source "${STATUS:?set STATUS to cluster-rank-status.sh}"
# shellcheck disable=SC1090
source "${HEAL:?set HEAL to cluster-generation-heal.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to cluster-link-guards.sh}"

# --- stubs -------------------------------------------------------------------
sysctl() { echo "{ sec = 1785031601, usec = 233215 } Sat Jul 25 22:06:41 2026"; }
hostname() { echo test-host; }
link_prep_ok() { return 0; }
peer_reachable() { return 0; }
set_wired_limit() { return 0; }
rank_reap_verified() { return 0; }
repair_link_prep() { return 1; }
alert() { printf '%s\n' "$1" >> "$pages"; }
stub_local_rev="aaaaaaaaaaaa"
stub_remote_rev="aaaaaaaaaaaa"
generation_local_rev() { printf '%s' "$stub_local_rev"; }
generation_remote_rev() { printf '%s' "$stub_remote_rev"; }

# pgrep through the seam: the heal must never touch a machine whose rank is
# serving, and rank_process_running is the REAL three-valued probe.
{
  printf '%s\n' "#!$BASH"
  cat << 'FAKE'
if [ -f "${FAKE_RANK_RUNNING_MARKER:-/nonexistent}" ]; then
  echo 4242
  exit 0
fi
exit 1
FAKE
} > "$state_dir/pgrep"
chmod +x "$state_dir/pgrep"
export CLUSTER_PGREP_BIN="$state_dir/pgrep"
export FAKE_RANK_RUNNING_MARKER="$state_dir/rank-running"

# launchctl through the seam. Job state is two markers: job-exists (submitted,
# not yet removed) and job-running (the rebuild is mid-flight).
{
  printf '%s\n' "#!$BASH"
  cat << 'FAKE'
printf '%s\n' "$*" >> "${FAKE_LC_LOG:?}"
case "$1" in
  print)
    [ -f "${FAKE_JOB_EXISTS:?}" ] || exit 113
    if [ -f "${FAKE_JOB_RUNNING:?}" ]; then
      echo "	state = running"
    else
      echo "	state = not running"
    fi
    ;;
  remove) rm -f "${FAKE_JOB_EXISTS:?}" ;;
  submit) touch "${FAKE_JOB_EXISTS:?}" ;;
esac
FAKE
} > "$state_dir/launchctl"
chmod +x "$state_dir/launchctl"
export CLUSTER_LAUNCHCTL_BIN="$state_dir/launchctl"
export FAKE_LC_LOG="$lc_log"
export FAKE_JOB_EXISTS="$state_dir/job-exists"
export FAKE_JOB_RUNNING="$state_dir/job-running"

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
      echo "  FAIL $label -> '$needle' missing from: $hay"
      fail=1
      ;;
  esac
}
submits() { grep -c '^submit' "$lc_log" || true; }
pages_sent() { grep -c . "$pages" || true; }
parity_is() {
  # Reset the cache so each case reads the parity the stubs now describe.
  rm -f "$gen_parity_file"
  stub_local_rev="$1"
  stub_remote_rev="$2"
}

echo "the HARD GATE: rank_start_preconditions_ok refuses mixed generations:"
parity_is aaaaaaaaaaaa bbbbbbbbbbbb # drift
if rank_start_preconditions_ok 2> /dev/null; then verdict=start; else verdict=refused; fi
check "drift refuses the start" refused "$verdict"
check "with the parity cause token" generation-parity "$PRECONDITION_REASON"
parity_is "" bbbbbbbbbbbb # unstamped (dirty build)
if rank_start_preconditions_ok 2> /dev/null; then verdict=start; else verdict=refused; fi
check "an unstamped build refuses too" refused "$verdict"
parity_is aaaaaaaaaaaa aaaaaaaaaaaa # ok
if rank_start_preconditions_ok 2> /dev/null; then verdict=start; else verdict=refused; fi
check "parity ok starts" start "$verdict"
parity_is aaaaaaaaaaaa "" # unverified (deploy branch unreachable)
if rank_start_preconditions_ok 2> /dev/null; then verdict=start; else verdict=refused; fi
check "unverified (offline) still starts — join's WARN semantics" start "$verdict"

echo
echo "a by-hand halt clear during drift is REJECTED (re-halt, revisions named):"
parity_is aaaaaaaaaaaa bbbbbbbbbbbb
halt_write "$halt_file" "$latch_file" test-cause "test detail"
rm -f "$halt_file" # the by-hand clear
if halt_clear_accepted "$halt_file" "$latch_file" "$kicks_file" 2> /dev/null; then
  verdict=accepted
else
  verdict=rejected
fi
check "the clear is rejected" rejected "$verdict"
contains "and the re-halt names the parity gate" "still-failing=generation-parity" "$(cat "$halt_file")"
rm -f "$halt_file" "$latch_file" "$kicks_file"

echo
echo "the DETACHED heal: submits a launchd job toward the deploy revision:"
parity_is aaaaaaaaaaaa bbbbbbbbbbbb
fact="$(generation_parity_cached "$gen_parity_file")"
generation_heal_maybe "$fact" "$attempts_file" || true
check "one submission" 1 "$(submits)"
contains "under its own label (not the watcher's process tree)" \
  "dev.mlx-cluster.generation-heal" "$(grep '^submit' "$lc_log")"
contains "rebuilding from the remote flake ref, pinned to the deploy rev" \
  "github:example/deploy/bbbbbbbbbbbb" "$(grep '^submit' "$lc_log")"
contains "always-exit-0 so launchctl submit cannot restart-loop a failing rebuild" \
  "|| true" "$(grep '^submit' "$lc_log")"
check "one attempt recorded for this rev" "bbbbbbbbbbbb 1" "$(cat "$attempts_file")"

echo
echo "...single-flight: a heal in progress is never doubled:"
touch "$FAKE_JOB_RUNNING"
generation_heal_maybe "$fact" "$attempts_file" || true
check "no second submission while the job runs" 1 "$(submits)"

echo
echo "...a finished heal is judged by RE-READING parity, not by trusting the job:"
rm -f "$FAKE_JOB_RUNNING"
generation_heal_maybe "$fact" "$attempts_file" || true
check "the finished job is removed" 1 "$(grep -c '^remove' "$lc_log" || true)"
check "and the parity cache is invalidated for a fresh read" absent \
  "$([ -f "$gen_parity_file" ] && echo present || echo absent)"

echo
echo "...still drifted after the retry budget: page ONCE and stop:"
fact="$(generation_parity_cached "$gen_parity_file")" # still drift (attempt 2)
generation_heal_maybe "$fact" "$attempts_file" || true
check "second (final) attempt submitted" 2 "$(submits)"
rm -f "$FAKE_JOB_EXISTS" # that attempt finished too
generation_heal_maybe "$fact" "$attempts_file" || true
generation_heal_maybe "$fact" "$attempts_file" || true
check "no third attempt (cap 2)" 2 "$(submits)"
check "exactly one page at the cap" 1 "$(pages_sent)"

echo
echo "...a NEW deploy revision opens a fresh budget:"
parity_is aaaaaaaaaaaa cccccccccccc
fact="$(generation_parity_cached "$gen_parity_file")"
generation_heal_maybe "$fact" "$attempts_file" || true
check "new rev submits again" 3 "$(submits)"
check "attempts reset to the new rev" "cccccccccccc 1" "$(cat "$attempts_file")"

echo
echo "...and a machine that is SERVING is never touched:"
rm -f "$FAKE_JOB_EXISTS"
touch "$FAKE_RANK_RUNNING_MARKER"
generation_heal_maybe "$fact" "$attempts_file" || true
check "no submission while the rank runs" 3 "$(submits)"
rm -f "$FAKE_RANK_RUNNING_MARKER"

echo
echo "...healthy parity heals nothing:"
parity_is aaaaaaaaaaaa aaaaaaaaaaaa
generation_heal_maybe "$(generation_parity_cached "$gen_parity_file")" "$attempts_file" || true
check "no submission at state=ok" 3 "$(submits)"

echo
echo "call sites and ORDER (a gate nothing runs before is not a gate):"
watcher="${WATCHER:?set WATCHER to cluster-link-watcher.sh}"
guards="${GUARDS:?}"
layers="${LAYERS:?set LAYERS to cluster-script-layers.nix}"
code() { grep -v '^[[:space:]]*#' "$1"; }
pin() {
  local label="$1" file="$2" pattern="$3"
  if code "$file" | grep -Eq "$pattern"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/ in $file"
    fail=1
  fi
}
pin "the watcher calls the heal" "$watcher" '(^|[^_[:alnum:]])generation_heal_maybe'
pin "the guards carry the parity rung" "$guards" 'PRECONDITION_REASON="generation-parity"'
pin "the heal layer is shipped in the watcher build" "$layers" 'cluster-generation-heal\.sh'
first_line() { grep -n "$2" "$1" | head -n1 | cut -d: -f1; }
parity_line="$(first_line "$watcher" 'parity_now="\$(generation_parity_cached')"
probe_line="$(first_line "$watcher" '/sbin/ping')"
if [ -n "$parity_line" ] && [ -n "$probe_line" ] && [ "$parity_line" -lt "$probe_line" ]; then
  echo "  ok   parity is read BEFORE the link probe — first fact of every tick"
else
  echo "  FAIL parity read (line ${parity_line:-none}) must precede the link probe (line ${probe_line:-none})"
  fail=1
fi
gate_line="$(first_line "$guards" 'PRECONDITION_REASON="generation-parity"')"
reap_line="$(first_line "$guards" 'rank_reap_verified')"
# `! link_prep_ok` is the RUNG; a bare link_prep_ok also matches the repair
# helper defined above the preconditions.
prep_line="$(first_line "$guards" '! link_prep_ok')"
if [ -n "$gate_line" ] && [ -n "$reap_line" ] && [ -n "$prep_line" ] &&
  [ "$gate_line" -lt "$reap_line" ] && [ "$gate_line" -lt "$prep_line" ]; then
  echo "  ok   the parity rung precedes every setup rung (reap, link prep)"
else
  echo "  FAIL parity rung (line ${gate_line:-none}) must precede reap (${reap_line:-none}) and prep (${prep_line:-none})"
  fail=1
fi

exit "$fail"
