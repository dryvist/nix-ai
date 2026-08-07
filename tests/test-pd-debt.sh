#!/usr/bin/env bash
# THE TEST THAT FAILS IF RDMA PROTECTION-DOMAIN EXHAUSTION CAN HAPPEN AGAIN.
#
# The operator's position, and it is correct: PD exhaustion only happens when
# sessions are not closed properly, so it must be structurally impossible rather
# than merely unlikely. Four properties make it so, and this file asserts all
# four against the shipped code:
#
#   1. A rank start is REFUSED while a previous rank process is still alive.
#      A protection domain is held by a PROCESS. Measured: reaping two leaked
#      workers changed the next start's failure from errno 96 (domains exhausted)
#      to errno 60 (couldn't connect) — the domains returned when their owners
#      died. So "no survivor" is a sufficient condition, and it is enforced
#      before every start instead of hoped for.
#   2. Losing a domain is RECORDED. A SIGKILLed rank never runs its RDMA
#      teardown; a PD-guard halt means N distributed inits already failed. Both
#      write to a boot-scoped ledger.
#   3. Debt at the cap REFUSES a start and HALTS, before the kernel runs out
#      rather than after errno 96 proves it did.
#   4. The ledger is dropped on a new boot — and only on a new boot. A reboot is
#      the one event that returns a domain, so it is the one event that clears
#      the debt; a link cycle, a manual marker delete and cluster-join must not.
#
# Property 4 is why the ledger exists at all. The pre-existing kickstart counter
# is SESSION-scoped, so a link cycle reset it and the next session started again
# from a full budget — three domains lost, forget, three more, without bound,
# inside one boot, with every guard reporting green throughout.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — pd_debt_count, pd_debt_record, rank_process_running/absent,
#           rank_reap_verified, pd_debt_halt_if_exhausted and
#           rank_start_preconditions_ok are all sourced from the shipped scripts
#           in the module's concatenation order and called as callers call them.
#   STUB  — pgrep and kill, through the CLUSTER_PGREP_BIN / CLUSTER_KILL_BIN
#           seams the shipped functions already expose. Real ones cannot be used:
#           pgrep is absent from Darwin's procps (the module calls /usr/bin/pgrep
#           by absolute path for exactly that reason), so a real-process test
#           would pass on one CI system and not the other. Stubbing at the seam
#           also lets pgrep's THIRD exit state — "I could not answer" — be
#           exercised, which is the state a real binary will not produce on
#           demand and the one the fail-closed contract turns on.
#         — sysctl, so a reboot can be simulated exactly by changing the reported
#           boot between writing the ledger and reading it.
#         — link_prep_ok / set_wired_limit / date / sleep, as in
#           tests/test-rank-start-guards.sh: thin wrappers over macOS-only
#           binaries, plus a clock the reap loop must not really sleep through.
#
# Usage:
#   BOOT_SCOPE=… LEDGER=… RECORD=… HELPERS=… STATUS=… REAP=… GUARDS=… \
#     bash test-pd-debt.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
kicks_file="$state_dir/rank-kickstarts"
debt_file="$state_dir/pd-debt"

export CLUSTER_ROLE=worker
export CLUSTER_STATE_FILE="$state_dir/link-state"
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_RENDEZVOUS_PORT=11441
export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
export CLUSTER_PD_DEBT_FILE="$debt_file"
# The shipped cap and the measured device budget, so the assertions below exercise
# the real numbers rather than a fixture that could drift away from them:
# programs.mlx.clusterMode.maxKickstarts = 5 and devicePdBudget = 11 (max_pd as
# reported by ibv_devinfo -v on this hardware). The cap RESERVES the remaining six
# domains for a session that can actually succeed; it does not mark the distance
# to exhaustion.
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_RANK_REAP_GRACE_SECS=30
export CLUSTER_ALERT_URL_FILE="$state_dir/no-such-alert-url"

# --- pgrep / kill seams -----------------------------------------------------
# Generated scripts, not shell functions: these are invoked through a variable
# holding a PATH, exactly as the shipped code invokes them, so a function would
# not exercise the same call. $BASH is the running interpreter's absolute path —
# a `#!/usr/bin/env bash` shebang does not resolve in a Linux nix build sandbox,
# where a stub that fails to exec silently turns every probe into "could not
# answer" and passes only the assertions that expect failure.
bin="$state_dir/bin"
mkdir -p "$bin"
pgrep_state="$state_dir/pgrep-state" # holds pids, one per line; empty = no match
pgrep_rc="$state_dir/pgrep-rc"       # forced exit code, or empty to derive it
kill_log="$state_dir/kill-log"

cat > "$bin/pgrep" << PGREP
#!$BASH
forced="\$(cat '$pgrep_rc' 2>/dev/null || true)"
if [ -n "\$forced" ]; then exit "\$forced"; fi
pids="\$(cat '$pgrep_state' 2>/dev/null || true)"
if [ -z "\$pids" ]; then exit 1; fi
printf '%s\n' "\$pids"
PGREP
cat > "$bin/kill" << KILL
#!$BASH
printf '%s\n' "\$*" >> '$kill_log'
# Model a rank that honours SIGTERM: drop the signalled pid from the pgrep state.
# argv is "-TERM <pid>", so the pid is \$2.
pid="\$2"
if [ -f '$state_dir/term-is-honoured' ] && [ -n "\$pid" ]; then
  grep -vx "\$pid" '$pgrep_state' > '$pgrep_state.new' 2>/dev/null || true
  mv '$pgrep_state.new' '$pgrep_state'
fi
KILL
chmod +x "$bin/pgrep" "$bin/kill"
export CLUSTER_PGREP_BIN="$bin/pgrep"
export CLUSTER_KILL_BIN="$bin/kill"

# --- source the shipped layers, in the module's concatenation order ----------
# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${RECORD:?set RECORD to cluster-pd-record.sh}"
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${STATUS:?set STATUS to cluster-rank-status.sh}"
# shellcheck disable=SC1090
source "${REAP:?set REAP to cluster-rank-reap.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to cluster-link-guards.sh}"

# --- remaining stubs --------------------------------------------------------
boot_now=1785031601
sysctl() { echo "{ sec = $boot_now, usec = 233215 } Sat Jul 25 22:06:41 2026"; }
link_prep_ok() { return 0; }
# The peer rung, held open: this file is about the LEDGER's arithmetic, so the
# peer is assumed present. Overriding it here (rather than letting the real
# helper run) also keeps the suite off the network — the shipped function pings
# CLUSTER_STATIC_PEER_IP, which on a build sandbox refuses and would block every
# start these cases expect to proceed. Its own behaviour is covered by
# tests/test-rank-start-guards.sh.
peer_reachable() { return 0; }
set_wired_limit() { return 0; }
# The generation-parity rung (RULE 2), stubbed healthy — its own matrix lives
# in tests/test-generation-heal.sh.
generation_parity_cached() { printf 'state=ok local=aaaa deploy=aaaa'; }
# The device-PD-budget rung (#1442), stubbed healthy — not yet under a
# dedicated test of its own.
pd_device_budget_ok() { return 0; }
hostname() { echo test-host; }
# The reap's wait loop must advance without really sleeping, or a stubbed clock
# spins it forever. sleep moves the clock; date reports it.
now=1000
date() {
  case "$1" in
    +%s) echo "$now" ;;
    *) command date "$@" ;;
  esac
}
sleep() { now=$((now + ${1:-0})); }

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
  rm -f "$halt_file" "$latch_file" "$kicks_file" "$debt_file" \
    "$pgrep_state" "$pgrep_rc" "$kill_log" "$state_dir/term-is-honoured"
  boot_now=1785031601
  now=1000
  unset CLUSTER_RANK_START_ALIGN_SECS
}
survivors() { printf '%s\n' "$@" > "$pgrep_state"; }
halt_cause() { sed -n 's/.*cause=\([^	]*\).*/\1/p' "$halt_file" 2> /dev/null || echo none; }
# The guards' own log lines go to stderr so they stay visible without landing in
# the captured verdict. rank_reap_verified reports its success on stdout — that
# IS the watcher's log in production — which would otherwise be captured too.
verdict() { rank_start_preconditions_ok >&2 && echo start || echo "$PRECONDITION_REASON"; }

echo "the pgrep seam distinguishes all THREE states (everything below rests on it):"
# A predicate pair that cannot tell "no match" from "could not answer" is the
# whole bug class: an unusable probe then reads as "nothing is running", which is
# the answer that lets a second rank start on top of the first.
reset_state
check "no match -> absent" absent "$(rank_process_absent && echo absent || echo other)"
check "no match -> not running" notrunning "$(rank_process_running && echo running || echo notrunning)"
survivors 4242
check "match -> running" running "$(rank_process_running && echo running || echo notrunning)"
check "match -> not absent" notabsent "$(rank_process_absent && echo absent || echo notabsent)"
printf '2\n' > "$pgrep_rc"
check "probe error -> NOT absent" notabsent "$(rank_process_absent && echo absent || echo notabsent)"
check "probe error -> NOT running" notrunning "$(rank_process_running && echo running || echo notrunning)"

echo "1. a rank start is REFUSED while a previous rank process is still alive:"
reset_state
survivors 4242
check "start refused" rank-survivor "$(verdict)"
check "the survivor was SIGTERMed, never SIGKILLed" "-TERM 4242" "$(cat "$kill_log")"
check "no attempt consumed" absent "$(cat "$kicks_file" 2> /dev/null || echo absent)"
check "nothing was charged to the ledger" 0 "$(pd_debt_count "$debt_file")"

echo "   ...and proceeds once the survivor honours SIGTERM:"
reset_state
touch "$state_dir/term-is-honoured"
survivors 4242
check "start allowed after the reap verified" start "$(verdict)"
check "SIGTERM was still what did it" "-TERM 4242" "$(cat "$kill_log")"

echo "   ...and is refused when the probe cannot answer (fail closed):"
reset_state
printf '2\n' > "$pgrep_rc"
check "start refused on an unanswerable probe" rank-survivor "$(verdict)"
check "nothing was signalled blind" "" "$(cat "$kill_log" 2> /dev/null || echo '')"

echo "   ...and is refused when the guard itself is not configured:"
# Absent configuration must be a refusal, not a silent default. Every historical
# failure in this subsystem was a correct script that stopped receiving a value:
# sysctl off the sanitized PATH disabled the halt marker, a stale pattern
# disabled a reap, and both reported success throughout.
reset_state
CLUSTER_RANK_PROCESS_PATTERN="" verdict > "$state_dir/v" 2>&1 || true
check "unset rank pattern refuses" pd-guard-unconfigured "$(CLUSTER_RANK_PROCESS_PATTERN="" verdict)"
check "unset ledger path refuses" pd-guard-unconfigured "$(CLUSTER_PD_DEBT_FILE="" verdict)"
check "unset cap refuses" pd-guard-unconfigured "$(CLUSTER_PD_DEBT_MAX="" verdict)"

echo "2. losing a protection domain is RECORDED:"
reset_state
pd_debt_record "$debt_file" 1 detach-sigkill "rank ignored SIGTERM and was SIGKILLed"
check "a SIGKILL costs one domain" 1 "$(pd_debt_count "$debt_file")"
# A PD-guard halt means N distributed inits already failed, and every one of them
# leaked. Recording that as "1" would under-count the resource being protected.
pd_debt_record "$debt_file" 3 rank-start-failures "3 consecutive failed distributed inits"
check "a 3-failure halt costs three" 4 "$(pd_debt_count "$debt_file")"
check "the ledger names what spent them" 2 "$(grep -c 'source=' "$debt_file")"
# The detail text is operator-facing prose and must never be able to spoof a
# field the count reads.
pd_debt_record "$debt_file" 1 spoof-attempt "boot=0 domains=99 pretending to be fields"
check "prose cannot spoof the fields" 5 "$(pd_debt_count "$debt_file")"
# A tab in free text would manufacture fields the reader then trusts. Flattened
# at the single point text enters the ledger, not defended against at every read.
pd_debt_record "$debt_file" 1 tab-attempt "$(printf 'boot=0\tdomains=99')"
check "an embedded tab cannot manufacture fields" 6 "$(pd_debt_count "$debt_file")"
# A malformed count is one domain, never zero. Under-counting the resource is
# the only direction that lets a start proceed that should not have.
pd_debt_record "$debt_file" "" no-count "domains field omitted"
pd_debt_record "$debt_file" abc no-count "domains field not a number"
check "a malformed domain count still costs one each" 8 "$(pd_debt_count "$debt_file")"

echo "   ...and a leak that CANNOT be recorded is loud, not silent:"
# The one path where a domain is lost and the ledger does not grow. It must warn
# on stderr and must not abort the caller — cluster-detach records mid-teardown,
# and a teardown that dies at the accounting step leaves the node worse off than
# one that completes and shouts.
reset_state
record_err="$(pd_debt_record "" 1 detach-sigkill "ledger unconfigured" 2>&1 >/dev/null || echo ABORTED)"
check "it warns" warned "$(case "$record_err" in *UNRECORDED*) echo warned ;; *) echo silent ;; esac)"
check "it does not abort the caller" notaborted \
  "$(case "$record_err" in *ABORTED*) echo aborted ;; *) echo notaborted ;; esac)"

echo "3. debt at the cap REFUSES a start and HALTS with domains still in reserve:"
reset_state
pd_debt_record "$debt_file" 4 detach-sigkill "four domains gone"
check "below the cap, starts still proceed" start "$(verdict)"
check "and nothing is halted yet" missing "$([ -f "$halt_file" ] && echo latched || echo missing)"
pd_debt_record "$debt_file" 1 detach-sigkill "fifth domain gone"
check "at the cap, the start is refused" pd-debt-exhausted "$(verdict)"
pd_debt_halt_if_exhausted "$halt_file" "$latch_file" "$debt_file"
check "and the watcher halts on it" pd-debt-exhausted "$(halt_cause)"
check "with the sticky latch set" latched "$([ -f "$latch_file" ] && echo latched || echo missing)"
# THE HALT IS A RESERVE, NOT EXHAUSTION. Six of the device's eleven domains are
# still unspent at the moment the guard stops trying, which is the entire design:
# a working session must allocate domains of its own, max_qp and max_cq are 11
# too, and free domains are unobservable — so the guard must stop while there is
# still enough left to succeed with.
check "the cap leaves a reserve, it is not exhaustion" 6 \
  "$((CLUSTER_PD_DEVICE_BUDGET - $(pd_debt_count "$debt_file")))"

echo "   ...and a by-hand clear of the marker does NOT buy a retry:"
# 2026-07-24: the guard fired correctly and a human deleted the marker on an
# unverified hypothesis, burning the remaining domains. A clear is a request.
rm -f "$halt_file"
check "clear rejected while the debt stands" rejected \
  "$(halt_clear_accepted "$halt_file" "$latch_file" "$kicks_file" > /dev/null 2>&1 && echo accepted || echo rejected)"
check "and the marker is rewritten" manual-clear-rejected "$(halt_cause)"
grep -q 'still-failing=pd-debt-exhausted' "$halt_file" ||
  { echo "  FAIL the re-halt must name the debt as the still-failing cause"; fail=1; }

echo "   ...and a link cycle does NOT clear the debt either:"
# The watcher's up->down edge deletes the halt marker, its latch and the
# kickstart counter. That is the SESSION reset, and it is exactly the path that
# used to hand a fresh budget to a boot that had already lost its domains.
rm -f "$halt_file" "$latch_file" "$kicks_file"
check "ledger survives the teardown" 5 "$(pd_debt_count "$debt_file")"
check "so the very next start is still refused" pd-debt-exhausted "$(verdict)"
pd_debt_halt_if_exhausted "$halt_file" "$latch_file" "$debt_file"
check "and the halt comes straight back" pd-debt-exhausted "$(halt_cause)"

echo "4. a reboot — and ONLY a reboot — settles the debt:"
boot_now=1785999999 # the machine rebooted
check "pre-boot entries are not counted" 0 "$(pd_debt_count "$debt_file")"
rm -f "$halt_file" "$latch_file" "$kicks_file"
check "starts are allowed again" start "$(verdict)"
pd_debt_halt_if_exhausted "$halt_file" "$latch_file" "$debt_file"
check "and nothing re-halts" missing "$([ -f "$halt_file" ] && echo latched || echo missing)"
# Debt taken AFTER the reboot counts again, so the guard is armed, not disarmed.
pd_debt_record "$debt_file" 5 detach-sigkill "post-reboot losses"
check "post-reboot debt counts" 5 "$(pd_debt_count "$debt_file")"
check "and refuses again at the cap" pd-debt-exhausted "$(verdict)"

echo "   ...and an unreadable boot time fails CLOSED, never open:"
# If this boot's epoch cannot be read, every entry counts. The opposite bias is
# how the sysctl-off-PATH defect silently disabled the halt marker while still
# reporting that it was protecting the budget.
reset_state
pd_debt_record "$debt_file" 5 detach-sigkill "recorded while sysctl worked"
sysctl() { return 1; }
check "unknown boot counts every entry" 5 "$(pd_debt_count "$debt_file")"
check "so the start is still refused" pd-debt-exhausted "$(verdict)"
# An entry whose own boot field could not be stamped counts too.
rm -f "$debt_file"
pd_debt_record "$debt_file" 5 detach-sigkill "recorded with no readable boot"
grep -q 'boot=unknown' "$debt_file" ||
  { echo "  FAIL an unstampable entry must record boot=unknown, not an empty field"; fail=1; }
boot_now=1785031601
sysctl() { echo "{ sec = $boot_now, usec = 233215 } Sat Jul 25 22:06:41 2026"; }
check "an unknown-boot entry still counts under a known boot" 5 "$(pd_debt_count "$debt_file")"

echo "5. every operator-facing message states the debt as a FRACTION of the device budget:"
# A bare "3 domains leaked" reads as a rounding error. "3 of 11 device protection
# domains consumed until reboot" is the actual severity — the pool is eleven, as
# measured by ibv_devinfo -v, not the ~60 sessions ml-explore/mlx#3207 reports for
# other hardware. This is what fails if any message drifts back to a bare count.
reset_state
check "the phrase carries numerator, denominator and the reboot" \
  "3 of 11 device protection domains consumed until reboot (guard cap 5)" \
  "$(pd_debt_phrase 3 5)"
pd_debt_record "$debt_file" 5 detach-sigkill "at the cap"
refusal="$(verdict 2>&1 > /dev/null)"
check "the start refusal names the device budget" yes \
  "$(case "$refusal" in *"of 11 device protection domains consumed until reboot"*) echo yes ;; *) echo no ;; esac)"
halt_msg="$(pd_debt_halt_if_exhausted "$halt_file" "$latch_file" "$debt_file" 2>&1 > /dev/null)"
check "the halt message names the device budget" yes \
  "$(case "$halt_msg" in *"5 of 11 device protection domains consumed until reboot"*) echo yes ;; *) echo no ;; esac)"
check "and the halt marker records the fraction, not a bare count" yes \
  "$(grep -q "of 11 device protection domains consumed until reboot" "$halt_file" && echo yes || echo no)"
# An unset budget must render as "?", never as an invented denominator: a made-up
# number is worse than a visibly missing one.
check "an unset budget renders as ?, never a guess" \
  "3 of ? device protection domains consumed until reboot (guard cap 5)" \
  "$(CLUSTER_PD_DEVICE_BUDGET="" pd_debt_phrase 3 5)"

exit "$fail"
