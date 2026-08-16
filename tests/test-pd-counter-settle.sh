#!/usr/bin/env bash
# THE TEST THAT FAILS IF A KICKSTART-COUNTER RESET CAN DISCARD LEAKED DOMAINS.
#
# tests/test-pd-debt.sh proves the ledger records a leak at the CAP and that only
# a reboot settles it. This file covers the hole underneath that: what happens to
# a counter that has not YET reached the cap when something resets it.
#
# THE DEFECT. The kickstart counter is session-scoped and four paths reset it —
# a rank that settled, a link cycle, cluster-join, and an accepted manual clear.
# The ledger was only ever WRITTEN at the cap, so a counter sitting at 1 or 2
# when any of those fired was simply deleted, and the domains those attempts had
# already leaked left no trace. That reopened the exact accumulation the ledger
# was introduced to close, one level down: leak two, blip the link, leak two
# again — ledger empty, every guard green, the kernel steadily poorer, and the
# host walking to a reboot-only state with nothing to show for it.
#
# It is not a hypothetical path. The watcher's link probe is a ping of the peer,
# so a peer that is UP but not participating (its own watcher halted, or its
# macOS Local Network permission denied so it never leaves `down`) leaves this
# host kickstarting into a rendezvous that never forms — one domain per attempt —
# while any transient link strike resets the counter before the cap is reached.
#
# THE INVARIANT ASSERTED HERE. `rank-kickstarts` counts launched attempts whose
# protection-domain cost is NOT yet in the ledger. Every reset transfers rather
# than discards, so no path can launder debt out of the accounting.
#
# ALSO ASSERTED (2026-08-16): a transfer that consulted only "how many attempts"
# and never "did any of them reach the call that actually allocates a domain"
# billed every jaccl TCP-bootstrap-only run as if it had leaked — the mechanism
# could not tell a Stage-A death (structurally cannot allocate a protection
# domain) from a Stage-B one (already has). $7/$8 let it check: a run whose
# outstanding attempts are ALL provably Stage-A-only bills nothing; any Stage-B
# evidence, or none either caller could classify, still bills the full count.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — pd_debt_settle_counter, pd_debt_record, pd_debt_count and
#           rank_failure_stage are sourced from the shipped scripts in the
#           module's own concatenation order and called exactly as the watcher,
#           cluster-join, cluster-detach and the guards call them.
#   STUB  — sysctl only, so the boot epoch is deterministic. Nothing in the
#           decision under test is stubbed.
#   SOURCE — part 3 reads the shipped scripts as text. Behaviour tests cannot
#           prove a CALL SITE still exists: a correct function that nobody calls
#           passes every behavioural assertion while the defect is fully back.
#           That is the failure mode this subsystem keeps producing (a sysctl off
#           the sanitized PATH, a stale process pattern — both inert, both
#           reporting success), so the call sites are pinned as text.
#
# Usage:
#   BOOT_SCOPE=… LEDGER=… RECORD=… STAGE=… SETTLE=… WATCHER=… JOIN=… DETACH=… \
#     GUARDS=… bash test-pd-counter-settle.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

kicks_file="$state_dir/rank-kickstarts"
debt_file="$state_dir/pd-debt"

# Deterministic boot epoch. current_boot_epoch shells out to sysctl; the ledger
# is boot-scoped, so a stable value is what lets a count be asserted at all.
bin_dir="$state_dir/bin"
mkdir -p "$bin_dir"
cat > "$bin_dir/sysctl" <<'STUB'
#!/usr/bin/env bash
echo "{ sec = 1750000000, usec = 0 } Fri Jan  1 00:00:00 2027"
STUB
chmod +x "$bin_dir/sysctl"
PATH="$bin_dir:$PATH"
export PATH
CLUSTER_SYSCTL_BIN="$bin_dir/sysctl"
export CLUSTER_SYSCTL_BIN

# Sourced in the module's concatenation order: boot scope, then the ledger read
# side, then the write side that carries pd_debt_settle_counter. HELPERS adds
# halt_write / halt_drop_if_pre_boot for part 4 below, which crosses a reboot.
# shellcheck source=/dev/null
. "${BOOT_SCOPE:?BOOT_SCOPE is required}"
# shellcheck source=/dev/null
. "${LEDGER:?LEDGER is required}"
# shellcheck source=/dev/null
. "${RECORD:?RECORD is required}"
# shellcheck source=/dev/null
. "${STAGE:?STAGE is required}"
# shellcheck source=/dev/null
. "${SETTLE:?SETTLE is required}"
# shellcheck source=/dev/null
. "${HELPERS:?HELPERS is required}"

failures=0
check() {
  local what="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "   ok   $what"
  else
    echo "   FAIL $what: want '$want', got '$got'" >&2
    failures=$((failures + 1))
  fi
}

reset_state() {
  rm -f "$kicks_file" "$debt_file"
}

echo "1. a reset TRANSFERS the counter into the ledger instead of dropping it:"
reset_state
printf '2\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 link-cycle "link went down mid-session"
check "two outstanding attempts become two domains" 2 "$(pd_debt_count "$debt_file")"
check "and the counter is cleared" missing \
  "$([ -f "$kicks_file" ] && echo present || echo missing)"
check "the ledger names what settled it" 1 "$(grep -c 'source=link-cycle' "$debt_file")"

echo "   ...and the transfer is NOT silent — it names the fraction of the budget:"
# The reset paths are exactly the moments an operator reads as "fine, it
# recovered". Booking domains there without saying so reproduces the original
# defect's experience even with correct accounting. Reported through the same
# pd_debt_phrase every other operator surface uses, so the denominator (the
# measured device budget) travels with the number.
reset_state
printf '2\n' > "$kicks_file"
settle_said="$(CLUSTER_PD_DEVICE_BUDGET=11 CLUSTER_PD_DEBT_MAX=5 \
  pd_debt_settle_counter "$debt_file" "$kicks_file" 0 link-cycle "link went down" 2>&1 >/dev/null)"
check "it says how many it charged" yes \
  "$(case "$settle_said" in *"2 protection domain(s) charged"*) echo yes ;; *) echo no ;; esac)"
check "it names the device budget as the denominator" yes \
  "$(case "$settle_said" in *"of 11 device protection domains"*) echo yes ;; *) echo no ;; esac)"
check "it names what spent them" yes \
  "$(case "$settle_said" in *link-cycle*) echo yes ;; *) echo no ;; esac)"

echo "   ...and stays quiet when it charges nothing:"
reset_state
printf '1\n' > "$kicks_file"
quiet_said="$(pd_debt_settle_counter "$debt_file" "$kicks_file" 1 rank-settled "first-time start" 2>&1 >/dev/null)"
check "no page-worthy noise on a clean start" "" "$quiet_said"

echo "   ...and a settled rank vindicates exactly ONE attempt, never all of them:"
# The rank now running holds its domain live rather than having leaked it. Every
# EARLIER attempt in the counter was superseded by another kickstart, so it
# failed, and a failed distributed init leaks whether or not a later one worked.
reset_state
printf '3\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 1 rank-settled "two failed before the one that settled"
check "three attempts with one success cost two" 2 "$(pd_debt_count "$debt_file")"

echo "   ...and a first-attempt success costs nothing:"
reset_state
printf '1\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 1 rank-settled "started first time"
check "no debt recorded" 0 "$(pd_debt_count "$debt_file")"
check "no ledger entry written at all" missing \
  "$([ -f "$debt_file" ] && echo present || echo missing)"
check "the counter is still cleared" missing \
  "$([ -f "$kicks_file" ] && echo present || echo missing)"

echo "   ...and an absent counter is not an error:"
# Every reset site runs on a 30s tick and may find no counter at all. Settling
# must be a no-op there, not a spurious domain and not a failure that aborts a
# teardown midway.
reset_state
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 link-cycle "nothing outstanding" \
  && rc=0 || rc=1
check "it succeeds" 0 "$rc"
check "and records nothing" 0 "$(pd_debt_count "$debt_file")"

echo "1b. the transfer is ERRNO-AWARE — a provably Stage-A-only run bills nothing:"
# ibv_alloc_pd lives in Stage B (RDMA queue-pair bring-up). A run whose every
# outstanding attempt only ever exhausted jaccl's TCP-bootstrap connect retry
# (Stage A) never reached it, so billing it protects a protection-domain
# budget those attempts could not have spent — the mechanism that produced a
# real fabricated ledger entry against a boot whose worker sat in SYN_SENT for
# every attempt, never once established, with zero trace on the coordinator.
rank_log="$state_dir/cluster-rank.error.log"
offset_file="$state_dir/rank-error-log-session-offset"
reset_state
printf '2\n' > "$kicks_file"
cat > "$rank_log" <<'EOF'
[jaccl] Connection attempt 0 waiting 1000 ms
[jaccl] Connection attempt 1 waiting 2000 ms
[jaccl] Connection attempt 2 waiting 4000 ms
[jaccl] Connection attempt 3 waiting 8000 ms
RuntimeError: [jaccl] Couldn't connect (error: 60)
EOF
printf '0\n' > "$offset_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 cluster-join \
  "attempts outstanding when cluster-join reset the session" "" "$rank_log" "$offset_file"
check "a stage-a-only run bills nothing" 0 "$(pd_debt_count "$debt_file")"
check "no ledger entry written at all" missing \
  "$([ -f "$debt_file" ] && echo present || echo missing)"
check "the counter is still cleared" missing \
  "$([ -f "$kicks_file" ] && echo present || echo missing)"
check "the offset marker goes with it" missing \
  "$([ -f "$offset_file" ] && echo present || echo missing)"

echo "   ...but ANY Stage-B evidence in the run still bills the full count:"
# One attempt in the run reaching Stage B is enough: it may have leaked, and
# there is no per-attempt record to say which one, so the whole outstanding
# count stays billed — the same fail-closed bias as the malformed-counter case
# below, just triggered by content instead of a bad number.
reset_state
printf '2\n' > "$kicks_file"
cat > "$rank_log" <<'EOF'
[jaccl] Changing queue pair to RTR failed with errno 96
EOF
printf '0\n' > "$offset_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 rank-start-failures \
  "2 consecutive failed distributed inits" "" "$rank_log" "$offset_file"
check "a stage-b run still bills the full count" 2 "$(pd_debt_count "$debt_file")"

echo "   ...and no log at all bills exactly as before this fix (unknown, not free):"
reset_state
printf '2\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 link-cycle "no log configured" \
  "" "" ""
check "an absent log is not treated as stage-a" 2 "$(pd_debt_count "$debt_file")"

echo "   ...and a run that predates this fix (no offset marker at all) bills as before:"
# A host mid-upgrade, or a run that started before the marker existed, has a
# log but no offset file. rank_failure_stage's own fail-closed default
# ("unknown" on an unreadable offset) is what keeps this the SAME behaviour as
# every call site had before this fix, not a new free pass.
reset_state
printf '2\n' > "$kicks_file"
cat > "$rank_log" <<'EOF'
[jaccl] Connection attempt 0 waiting 1000 ms
RuntimeError: [jaccl] Couldn't connect (error: 60)
EOF
rm -f "$offset_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 link-cycle "no offset marker" \
  "" "$rank_log" "$offset_file"
check "no offset marker still bills (fail closed)" 2 "$(pd_debt_count "$debt_file")"
rm -f "$rank_log" "$offset_file"

echo "2. a malformed counter is FAIL-CLOSED — never a free reset:"
# Under-counting is the only direction that lets a start proceed that should not
# have, so a vindicated count that is not a number must not be able to subtract.
reset_state
printf '2\n' > "$kicks_file"
# 0x10, not "abc". Bash arithmetic reads a bare word as an unset variable worth
# zero, so "abc" behaves identically with and without the numeric guard and
# would assert nothing. A hex literal is the case that discriminates: the guard
# rejects it to 0 (debt 2), while an unguarded subtraction reads 16, computes a
# NEGATIVE debt, and records nothing at all — a free reset, which is the exact
# direction that must be impossible.
pd_debt_settle_counter "$debt_file" "$kicks_file" 0x10 rank-settled "non-numeric vindication"
check "a non-numeric vindication subtracts nothing" 2 "$(pd_debt_count "$debt_file")"

reset_state
printf 'garbage\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 link-cycle "unreadable counter"
check "an unreadable counter records nothing but still clears" 0 "$(pd_debt_count "$debt_file")"
check "the counter is gone either way" missing \
  "$([ -f "$kicks_file" ] && echo present || echo missing)"

echo "   ...and vindication can never manufacture a NEGATIVE debt:"
reset_state
printf '1\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 5 rank-settled "vindication exceeds the count"
check "no ledger entry" 0 "$(pd_debt_count "$debt_file")"

echo "3. every reset CALL SITE goes through the settle — pinned as source:"
# A correct function nobody calls passes part 1 and 2 while the defect is fully
# back. So: the shipped scripts must contain no `rm` of the kickstart counter
# outside pd_debt_settle_counter itself, which is the single sanctioned reset.
#
# cluster-link-guards.sh is deliberately NOT in this list. halt_clear_accepted
# clears the counter directly, and must: a cap-halt settles at the cap (which
# records the debt and zeroes the counter), so an accepted clear finds nothing
# outstanding, and settling again would re-record the capped attempts and
# re-halt on the next tick — making the documented recovery a permanent no-op.
# The exemption is safe only because the cap path settles, which is pinned
# below ("the watcher settles at the cap instead of recording bare").
for f in "${WATCHER:?WATCHER is required}" "${JOIN:?JOIN is required}"; do
  name="$(basename "$f")"
  # Code lines only — the comments in these files legitimately discuss the old
  # `rm -f "$kicks_file"` behaviour they replaced, and a scan that matched prose
  # would fail on its own changelog.
  stray="$(grep -vE '^[[:space:]]*#' "$f" | grep -cE 'rm[[:space:]]+-[a-z]*f?[a-z]*[^|;&]*\$\{?kicks_file' || true)"
  check "$name never removes the counter directly" 0 "$stray"
done

# ...and each site that resets a session actually calls the settle. Absence here
# means a reset path was added or restored without transferring its debt.
check "the watcher settles on a settled rank" 1 \
  "$(grep -c 'pd_debt_settle_counter .* 1 "rank-settled"' "$WATCHER" || true)"
check "the watcher settles on a link cycle" 1 \
  "$(grep -c 'pd_debt_settle_counter .* 0 "link-cycle"' "$WATCHER" || true)"
check "the watcher settles at the cap instead of recording bare" 1 \
  "$(grep -c 'pd_debt_settle_counter .* 0 "rank-start-failures"' "$WATCHER" || true)"
check "cluster-join settles before clearing the session" 1 \
  "$(grep -c 'pd_debt_settle_counter .* 0 "cluster-join"' "$JOIN" || true)"
# The documented recovery must survive: an accepted manual clear resets the
# counter outright, and must NOT settle it (see the exemption above). Pinned in
# both directions so neither the reset nor the exemption can silently flip.
# The literal is assembled rather than single-quoted: a '$' inside single quotes
# reads as an unexpanded-expression mistake (SC2016) to every future reviewer and
# linter, and the sigil here is genuinely part of the source text being matched.
dollar='$'
accepted_clear_reset="rm -f \"${dollar}latch_file\" \"${dollar}kicks_file\""
check "an accepted clear resets the counter outright" 1 \
  "$(grep -vE '^[[:space:]]*#' "${GUARDS:?GUARDS is required}" |
    grep -cF "$accepted_clear_reset" || true)"
check "and does not settle it" 0 \
  "$(grep -vE '^[[:space:]]*#' "$GUARDS" | grep -c 'pd_debt_settle_counter' || true)"

# The cap path must NOT also call the bare recorder: recording and then leaving
# the counter populated is how the same attempts got billed twice.
check "the cap path no longer records bare" 0 \
  "$(grep -vE '^[[:space:]]*#' "$WATCHER" | grep -c 'pd_debt_record ' || true)"

# ...and each settle call actually PASSES the stage-classification args, not
# just calls the function. A call site that forgot $7/$8 bills exactly as
# before this fix while every assertion above still passes — the same "correct
# function nobody wires up" failure mode part 3's own opening comment names,
# one call site at a time. -A4 covers each call's line-continuation tail.
check "the watcher's rank-settled call passes the rank log" 1 \
  "$(grep -A4 'pd_debt_settle_counter .* 1 "rank-settled"' "$WATCHER" |
    grep -c 'CLUSTER_RANK_ERROR_LOG' || true)"
check "the watcher's link-cycle call passes the rank log" 1 \
  "$(grep -A4 'pd_debt_settle_counter .* 0 "link-cycle"' "$WATCHER" |
    grep -c 'CLUSTER_RANK_ERROR_LOG' || true)"
check "the watcher's cap-path call passes the rank log" 1 \
  "$(grep -A4 'pd_debt_settle_counter .* 0 "rank-start-failures"' "$WATCHER" |
    grep -c 'CLUSTER_RANK_ERROR_LOG' || true)"
check "cluster-join's call passes the rank log" 1 \
  "$(grep -A4 'pd_debt_settle_counter .* 0 "cluster-join"' "$JOIN" |
    grep -c 'CLUSTER_RANK_ERROR_LOG' || true)"
check "cluster-detach settles before clearing the session" 1 \
  "$(grep -vE '^[[:space:]]*#' "${DETACH:?DETACH is required}" |
    grep -c 'pd_debt_settle_counter ' || true)"
detach_settle_block="$(grep -vE '^[[:space:]]*#' "$DETACH" | grep -A4 'pd_debt_settle_counter ')"
check "...naming cluster-detach as the source" 1 \
  "$(printf '%s\n' "$detach_settle_block" | grep -c '"cluster-detach"' || true)"
check "...and passing the rank log" 1 \
  "$(printf '%s\n' "$detach_settle_block" | grep -c 'CLUSTER_RANK_ERROR_LOG' || true)"

echo "4. a halt marker left over from a PREVIOUS boot never suppresses THIS boot's charge:"
# 2026-08-08 night watch: a stale halt from an earlier boot sat on disk when a
# fresh cycle burned 5 kickstarts under a NEW boot. Reproduces exactly that
# shape: write a halt under the OLD boot, cross a real reboot, then run the
# cap path (halt_write + pd_debt_settle_counter) exactly as
# cluster-link-watcher.sh does at the kickstart cap. The drop must not eat the
# fresh charge, and the fresh marker must carry the NEW boot, not the old one.
reset_state
halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
rm -f "$halt_file" "$latch_file"
# A shell function shadows the file-based stub for command -v — same
# reboot-simulation idiom test-pd-debt.sh and test-halt-boot-scope.sh already
# use, and it sidesteps rewriting an executable file mid-test (the file-swap
# approach passed locally but failed on the CI runner).
sysctl() { echo "{ sec = 1750000000, usec = 0 } stale boot"; }
halt_write "$halt_file" "$latch_file" rank-start-failures "prior cycle's 5 failures"
sysctl() { echo "{ sec = 1750086400, usec = 0 } after reboot"; }
halt_drop_if_pre_boot "$halt_file" "$latch_file" "$kicks_file"
check "the stale marker is gone after the reboot" missing \
  "$([ -f "$halt_file" ] && echo present || echo missing)"
printf '5\n' > "$kicks_file"
halt_write "$halt_file" "$latch_file" rank-start-failures "5 consecutive failed rank starts"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 rank-start-failures \
  "5 consecutive failed distributed inits, one protection domain each"
recorded_boot="$(awk -F'\t' '{for (i=1;i<=NF;i++) if ($i ~ /^boot=/) {sub(/^boot=/,"",$i); print $i; exit}}' "$halt_file")"
check "the fresh marker carries the NEW boot, not the stale one" 1750086400 "$recorded_boot"
check "the ledger gained the current-boot charge" 5 "$(pd_debt_count "$debt_file")"

if [ "$failures" -ne 0 ]; then
  echo "FAILED: $failures assertion(s)" >&2
  exit 1
fi
echo "PASS: a kickstart-counter reset cannot discard leaked protection domains"
