#!/usr/bin/env bash
# Exercises the peer-armed handshake and the cross-boot, cause-keyed
# protection-domain budget — modules/mlx/scripts/cluster-peer-state.sh and
# modules/mlx/scripts/cluster-pd-cause.sh.
#
# WHAT THIS PINS. Every case below is a way the 2026-08-07 and 2026-08-08 nights
# could recur. A host that pings but cannot rendezvous must cost ZERO protection
# domains, a host whose watcher has died must not be able to grant permission
# from a stale file, a halted pair must re-arm without a human replugging a
# cable that was never out, and a cause that keeps spending domains across
# reboots must eventually stop.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL — peer_state_write, peer_armed_ok, peer_rearm_maybe, pd_cause_total and
#          pd_cause_budget_ok are sourced from the shipped scripts and called as
#          the watcher calls them. The JSON on the wire is the real jq output.
#   STUB — curl (a shell function replaying a canned body and status, the same
#          seam CLUSTER_PING_BIN and CLUSTER_NETSTAT_BIN already provide),
#          current_boot_epoch, and mem_headroom_ok — stubbed FAILING in one case
#          purely to prove peer_state_write no longer consults it (the
#          pre-quiesce sample must not reach the published armed bit).
#
# Peer address is an RFC 5737 documentation address, never a real link address.
#
# Usage:
#   BOOT_SCOPE=... LEDGER=... CAUSE=... RECORD=... PEER_STATE=... STAGE=... \
#     SETTLE=... HELPERS=... bash test-peer-armed-gate.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
seen_file="$state_dir/peer-state-last"
debt_file="$state_dir/pd-debt"
published="$state_dir/peer-state.json"

export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_PEER_STATE_PORT=11442
export CLUSTER_PEER_STATE_TIMEOUT_SECS=2
export CLUSTER_PEER_STATE_STALE_SECS=90
export CLUSTER_PD_DEBT_FILE="$debt_file"
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_PD_CAUSE_BUDGET=3
export CLUSTER_SHARD_MEMORY_MB=0
export CLUSTER_CURL_BIN=fake_curl

# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${CAUSE:?set CAUSE to cluster-pd-cause.sh}"
# shellcheck disable=SC1090
source "${RECORD:?set RECORD to cluster-pd-record.sh}"
# shellcheck disable=SC1090
source "${PEER_STATE:?set PEER_STATE to cluster-peer-state.sh}"
# shellcheck disable=SC1090
source "${STAGE:?set STAGE to cluster-pd-stage.sh}"
# shellcheck disable=SC1090
source "${SETTLE:?set SETTLE to cluster-pd-settle.sh}"
# halt_write and halt_cause_file — the cross-boot cause record the budget falls
# back to once a reboot has cleared the latch.
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"

# --- stubs ------------------------------------------------------------------
# The boot epoch is fixed so ledger entries are unambiguously "this boot", and
# the memory rung is stubbed because vm_stat does not exist on the runner. Both
# are overridden AFTER sourcing, so the shipped definitions are the ones being
# replaced rather than shadowed by load order.
current_boot_epoch() { printf '1785031601'; }
mem_ok=0
mem_headroom_ok() { [ "$mem_ok" = 0 ]; }

# Replays a canned body. Exit 1 with no body is the shape curl -fsS gives for a
# refused connection, which is what an absent peer looks like.
curl_body=""
curl_rc=0
fake_curl() {
  [ "$curl_rc" = 0 ] || return 1
  printf '%s' "$curl_body"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

peer_json() {
  # $1 armed, $2 wired_ok, $3 generation, $4 ts, $5 boot
  jq -nc --argjson armed "$1" --argjson wired "$2" --arg gen "$3" \
    --argjson ts "$4" --argjson boot "$5" \
    '{armed:$armed, halted_cause:null, boot:$boot, wired_ok:$wired, generation:$gen, ts:$ts}'
}

now="$(date +%s)"
ok_parity="state=ok local=abc123 deploy=abc123"

# --- 1. what this host PUBLISHES --------------------------------------------
# Healthy: armed and wired_ok both true, generation taken from the parity fact.
peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file"
[ "$(jq -r '.armed' "$published")" = "true" ] || fail "healthy host must publish armed=true"
[ "$(jq -r '.wired_ok' "$published")" = "true" ] || fail "healthy host must publish wired_ok=true"
[ "$(jq -r '.generation' "$published")" = "abc123" ] || fail "published generation must come from the parity fact"
[ "$(jq -r '.halted_cause' "$published")" = "null" ] || fail "an unhalted host has no halted_cause"
[ "$(jq -r '.boot' "$published")" = "1785031601" ] || fail "published boot must be this boot"

# THE MUTUAL DEADLOCK, PINNED. A worker that halts on rank-start-failures
# because the coordinator never joined must not publish armed=false over it —
# doing so would make the coordinator refuse on "peer is not armed", which
# would keep the worker's retries failing and re-earning the halt: a stable
# mutual refusal, the state cluster-link-truths.md §1 forbids. A halt on a
# PEER-DERIVED cause must therefore still publish armed=true. The cause itself
# is still published (it is the state the peer most needs to see), and the
# decision is logged.
for exempt_cause in rank-start-failures peer-absent peer-halted; do
  printf '%s\tcause=%s\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" "$exempt_cause" > "$halt_file"
  log="$(peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file" 2>&1)"
  [ "$(jq -r '.armed' "$published")" = "true" ] \
    || fail "a halt on peer-derived cause $exempt_cause must NOT disarm — that fold is the mutual deadlock"
  [ "$(jq -r '.halted_cause' "$published")" = "$exempt_cause" ] \
    || fail "a halted host must publish the cause it halted on ($exempt_cause)"
  [ "$(jq -r '.wired_ok' "$published")" = "true" ] \
    || fail "a peer-derived halt says nothing about wired memory ($exempt_cause)"
  case "$log" in
    *"still publishing armed=true"*) ;;
    *) fail "the exemption is a guard decision and must log itself ($exempt_cause): $log" ;;
  esac
done

# A halt on a LOCAL incapacity still disarms — this host genuinely cannot join.
for local_cause in pd-debt-exhausted manual-clear-rejected no-token-progress; do
  printf '%s\tcause=%s\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" "$local_cause" > "$halt_file"
  log="$(peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file" 2>&1)"
  [ "$(jq -r '.armed' "$published")" = "false" ] \
    || fail "a halt on local cause $local_cause must publish armed=false"
  [ "$(jq -r '.halted_cause' "$published")" = "$local_cause" ] \
    || fail "a halted host must publish the cause it halted on ($local_cause)"
  case "$log" in
    *"armed=false"*) ;;
    *) fail "a disarm must log its reason ($local_cause): $log" ;;
  esac
done

# The exemption is an ALLOWLIST: a cause nobody has classified must fail closed.
printf '%s\tcause=cause-nobody-classified\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" > "$halt_file"
peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file" 2> /dev/null
[ "$(jq -r '.armed' "$published")" = "false" ] || fail "an unrecognised halt cause must disarm"

# insufficient-memory-persistent is the durable memory verdict: it disarms AND
# sets wired_ok=false, because its remedy (a reboot, to return unreclaimed
# wired Metal) differs from every other term.
printf '%s\tcause=insufficient-memory-persistent\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" > "$halt_file"
peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file" 2> /dev/null
[ "$(jq -r '.armed' "$published")" = "false" ] || fail "a persistent memory halt must disarm"
[ "$(jq -r '.wired_ok' "$published")" = "false" ] \
  || fail "a persistent memory halt must publish wired_ok=false — its remedy is a reboot"
rm -f "$halt_file"

# Generation drift disarms, because a mixed mlx/JACCL stack cannot mesh.
peer_state_write "$published" "state=drift local=abc123 deploy=def456" "$halt_file" "$debt_file"
[ "$(jq -r '.armed' "$published")" = "false" ] || fail "a drifted host must publish armed=false"

# THE FALSE DISARM, PINNED FROM THE OTHER SIDE. peer_state_write used to fold
# a raw mem_headroom_ok sample into armed — measured at the top of the tick,
# against a WARM standalone-serving footprint, i.e. BEFORE the quiesce that
# would return that memory, which can publish armed=false with
# halted_cause=none for no real cause. The publisher must not consult the
# pre-quiesce sample at all: mem_headroom_ok failing with no halt standing
# changes NOTHING published.
# The must-fail direction of this exemption is the insufficient-memory-
# persistent case above — the durable, dwelled verdict still disarms.
mem_ok=1
peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file"
[ "$(jq -r '.armed' "$published")" = "true" ] \
  || fail "a pre-quiesce memory sample must not disarm — quiescing would free that memory"
[ "$(jq -r '.wired_ok' "$published")" = "true" ] \
  || fail "wired_ok names the durable halt verdict, never the pre-quiesce sample"
mem_ok=0

# Debt at the cap disarms: this host has no domains left to spend.
printf '%s\tboot=1785031601\tdomains=5\tsource=rank-start-failures\tcause=rank-start-failures\tdetail\n' \
  "2026-08-08T00:00:00Z" > "$debt_file"
peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file"
[ "$(jq -r '.armed' "$published")" = "false" ] || fail "debt at the cap must publish armed=false"
: > "$debt_file"

# --- 2. the GATE decision table ---------------------------------------------
# peer armed x wired ok x generation match, plus reachability and staleness.
assert_gate() {
  # $1 expected (ok|refuse), $2 label
  if peer_armed_ok "$ok_parity"; then
    [ "$1" = ok ] || fail "$2: gate allowed a start it must refuse"
  else
    [ "$1" = refuse ] || fail "$2: gate refused a start it must allow ($PEER_GATE_REASON)"
  fi
}

curl_rc=0
curl_body="$(peer_json true true abc123 "$now" 42)"
assert_gate ok "armed + headroom + same generation"

curl_body="$(peer_json false true abc123 "$now" 42)"
assert_gate refuse "peer not armed"

curl_body="$(peer_json true false abc123 "$now" 42)"
assert_gate refuse "peer has no memory headroom"

curl_body="$(peer_json true true def456 "$now" 42)"
assert_gate refuse "generation mismatch"

curl_body="$(peer_json true true abc123 "$((now - 600))" 42)"
assert_gate refuse "stale state from a watcher that stopped publishing"

curl_rc=1
curl_body=""
assert_gate refuse "peer unreachable"

# A body that is not JSON must never read as permission.
curl_rc=0
curl_body="<html>not the responder</html>"
assert_gate refuse "unparseable body"

# Port 0 disables the channel outright — the documented rollout escape hatch.
curl_rc=1
CLUSTER_PEER_STATE_PORT=0 assert_gate ok "channel disabled by port 0"

# Both generations empty (parity disabled on both hosts) compares equal, so
# turning parity checking off must not also wedge this gate.
curl_rc=0
curl_body="$(peer_json true true "" "$now" 42)"
if ! peer_armed_ok "state=disabled local= deploy="; then
  fail "parity disabled on both sides must not be read as a generation mismatch"
fi

# --- 3. auto re-arm ----------------------------------------------------------
rm -f "$seen_file"
curl_body="$(peer_json true true abc123 "$now" 42)"

# No halt: nothing to re-arm, and the last-seen record is dropped. That deletion
# is what makes the first poll of the NEXT halt a transition — without it, a
# host that halts while its peer was healthy and unchanged throughout would see
# no transition ever and stay halted until a human replugged the cable.
printf 'armed boot=42\n' > "$seen_file"
peer_rearm_maybe "$halt_file" "$latch_file" "$seen_file" "$ok_parity" "$debt_file"
[ ! -f "$seen_file" ] || fail "with no halt standing the last-seen record must be dropped"

# Halted, peer armed, no record: exactly one re-arm.
printf '%s\tcause=peer-absent\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" > "$halt_file"
printf 'peer-absent\n' > "$latch_file"
peer_rearm_maybe "$halt_file" "$latch_file" "$seen_file" "$ok_parity" "$debt_file"
[ ! -f "$halt_file" ] || fail "an armed peer with no prior record must clear the halt"
[ -f "$latch_file" ] || fail "auto re-arm must KEEP the latch so the next tick re-verifies"

# ...and only one. The same unchanged peer must not re-arm again.
printf '%s\tcause=peer-absent\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" > "$halt_file"
peer_rearm_maybe "$halt_file" "$latch_file" "$seen_file" "$ok_parity" "$debt_file"
[ -f "$halt_file" ] || fail "an unchanged armed peer must not re-arm a second time"

# A peer reboot IS a transition: its boot epoch changed.
curl_body="$(peer_json true true abc123 "$now" 43)"
peer_rearm_maybe "$halt_file" "$latch_file" "$seen_file" "$ok_parity" "$debt_file"
[ ! -f "$halt_file" ] || fail "a peer boot-epoch change must count as a transition"

# A peer that is not armed never re-arms this host, and records that so the
# eventual armed state is seen as a transition.
printf '%s\tcause=peer-absent\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" > "$halt_file"
curl_body="$(peer_json false true abc123 "$now" 43)"
peer_rearm_maybe "$halt_file" "$latch_file" "$seen_file" "$ok_parity" "$debt_file"
[ -f "$halt_file" ] || fail "a peer that is not armed must not clear this host's halt"
curl_body="$(peer_json true true abc123 "$now" 43)"
peer_rearm_maybe "$halt_file" "$latch_file" "$seen_file" "$ok_parity" "$debt_file"
[ ! -f "$halt_file" ] || fail "notarmed -> armed must be a transition"

# Debt at the boot cap refuses to re-arm: re-arming into a guard that will
# re-halt on the next tick is churn.
printf '%s\tcause=peer-absent\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" > "$halt_file"
rm -f "$seen_file"
printf '%s\tboot=1785031601\tdomains=5\tsource=rank-start-failures\tcause=rank-start-failures\tx\n' \
  "2026-08-08T00:00:00Z" > "$debt_file"
peer_rearm_maybe "$halt_file" "$latch_file" "$seen_file" "$ok_parity" "$debt_file"
[ -f "$halt_file" ] || fail "re-arm must refuse while the boot-scoped ledger is at its cap"
: > "$debt_file"

# --- 4. cause-keyed cross-boot totals ---------------------------------------
: > "$debt_file"
[ "$(pd_cause_total "$debt_file" peer-absent)" = 0 ] || fail "an empty ledger totals zero"

# Sums domains= across DIFFERENT boots — that is the whole point, because
# pd_debt_count deliberately stops at the current boot and a reboot is exactly
# how a repeating defect hides.
pd_debt_record "$debt_file" 2 rank-start-failures "first boot" peer-absent
current_boot_epoch() { printf '1785099999'; }
pd_debt_record "$debt_file" 1 rank-start-failures "second boot" peer-absent
[ "$(pd_cause_total "$debt_file" peer-absent)" = 3 ] \
  || fail "cause totals must span boots (got $(pd_cause_total "$debt_file" peer-absent))"
[ "$(pd_debt_count "$debt_file")" = 1 ] \
  || fail "the boot-scoped count must still see only this boot"

# A different cause is a different bucket.
[ "$(pd_cause_total "$debt_file" warm-wedged)" = 0 ] || fail "causes must not bleed between buckets"

# Entries written before cause= existed land in a bucket no halt cause queries,
# so an old ledger never blocks anything.
printf '%s\tboot=1785099999\tdomains=9\tsource=legacy\tno cause field here\n' \
  "2026-08-01T00:00:00Z" >> "$debt_file"
[ "$(pd_cause_total "$debt_file" peer-absent)" = 3 ] \
  || fail "a legacy entry with no cause= must not count against a real cause"

# Prose in the final field must not be able to spoof a field, exactly as
# pd_debt_count already guarantees.
printf '%s\tboot=1785099999\tdomains=1\tsource=legacy\tcause=peer-absent domains=99 in the detail\n' \
  "2026-08-01T00:00:00Z" >> "$debt_file"
[ "$(pd_cause_total "$debt_file" peer-absent)" = 3 ] \
  || fail "a cause= inside the detail text must not be read as a field"

# --- 4b. THE BUCKET MUST ACTUALLY RECEIVE DEPOSITS --------------------------
# The budget is only as good as what reaches its bucket, and the path that
# nearly missed it is the one that matters most. A standdown writes the latch
# (cause peer-absent) and leaves the kickstart counter outstanding; the link
# cycle settles it later under source=link-cycle. Billed to the source alone,
# every domain a standdown spent would land in a bucket no halt latch ever
# names, and pd_cause_total peer-absent would read zero forever while the same
# defect burned a fresh budget every boot. The watcher therefore reads the latch
# at that settle and passes it as the cause.
: > "$debt_file"
kicks_file="$state_dir/rank-kickstarts"
printf '2\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 "link-cycle" \
  "attempts outstanding when the link went down" "peer-absent"
[ "$(pd_cause_total "$debt_file" peer-absent)" = 2 ] \
  || fail "a link-cycle settle must bill the standing halt cause, not just its own source"
[ "$(pd_cause_total "$debt_file" link-cycle)" = 0 ] \
  || fail "the mechanism must not also be charged as the reason"
[ ! -f "$kicks_file" ] || fail "the counter must still be cleared"

# With no latch standing the watcher falls back to the source token, which no
# halt cause names, so an ordinary unplug never fills anyone's budget.
printf '2\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 "link-cycle" "no halt was standing"
[ "$(pd_cause_total "$debt_file" peer-absent)" = 2 ] \
  || fail "an unplug with no halt standing must not charge a halt cause"

# --- 5. the budget, and the ONLY thing that clears it -----------------------
# Rebuild the bucket to exactly the budget, independent of what 4/4b left.
: > "$debt_file"
pd_debt_record "$debt_file" 3 rank-start-failures "at the budget" peer-absent
printf 'peer-absent\n' > "$latch_file"
if pd_cause_budget_ok "$latch_file"; then
  fail "a cause at the cross-boot budget must refuse"
fi
# The refusal explains itself on stderr rather than through a variable — see
# pd_cause_budget_ok for why a cross-layer variable would be enforced by nothing.
# Captured rather than piped to grep: pipefail would surface the function's own
# (correct) nonzero refusal as a pipeline failure and fail the wrong assertion.
budget_msg="$(pd_cause_budget_ok "$latch_file" 2>&1 || true)"
case "$budget_msg" in
  *'cross-boot budget'*) ;;
  *) fail "a refusal must name the budget it hit" ;;
esac

# A reboot does NOT clear it. That is the entire reason this axis exists.
current_boot_epoch() { printf '1785200000'; }
if pd_cause_budget_ok "$latch_file"; then
  fail "a reboot must NOT clear the cross-boot cause budget"
fi

# Neither does a different cause's latch.
printf 'warm-wedged\n' > "$latch_file"
pd_cause_budget_ok "$latch_file" || fail "an unrelated cause must not be blocked"

# Only an explicit operator entry resets the bucket.
printf 'peer-absent\n' > "$latch_file"
pd_debt_record "$debt_file" 0 cause-budget-reset "operator reviewed the handshake" peer-absent
[ "$(pd_cause_total "$debt_file" peer-absent)" = 0 ] || fail "a reset entry must zero the bucket"
pd_cause_budget_ok "$latch_file" || fail "a reset entry must lift the refusal"

# Spending after the reset counts again, so the reset is a fresh start rather
# than an exemption.
pd_debt_record "$debt_file" 3 rank-start-failures "after the reset" peer-absent
if pd_cause_budget_ok "$latch_file"; then
  fail "domains spent AFTER a reset must count toward the budget again"
fi

# No latch and no cross-boot record = no would-be cause = nothing to refuse.
rm -f "$latch_file" "$(halt_cause_file "$latch_file")"
pd_cause_budget_ok "$latch_file" || fail "with no halt latch there is no cause to refuse"

# --- 5b. THE SECOND THING THAT CLEARS IT: A CLUSTER THAT DEMONSTRABLY WORKS --
# The operator entry above is a statement that somebody looked. A soak PASS is
# the machine making the same statement with better evidence: it is only
# reachable after this host formed the cluster, passed the full health gate, and
# then answered a real completion from the running pipeline. A cause cannot at
# once be why this host cannot cluster and be true of a host that is clustered
# and serving. Its call site is pinned in tests/test-soak-busy-vs-wedged.sh.
: > "$debt_file"
pd_debt_record "$debt_file" 3 rank-start-failures "at the budget" peer-absent
printf 'peer-absent\n' > "$latch_file"
if pd_cause_budget_ok "$latch_file"; then
  fail "the bucket must be at the budget before the settle is exercised"
fi
before_lines="$(wc -l < "$debt_file" | tr -d ' ')"
settle_msg="$(pd_cause_settle_on_evidence "$latch_file")"
[ "$(pd_cause_total "$debt_file" peer-absent)" = 0 ] || fail "a soak PASS must zero the settled bucket"
pd_cause_budget_ok "$latch_file" || fail "a soak PASS must lift the refusal it settled"
case "$settle_msg" in
  *"'peer-absent'"*"3 domain(s) retired"*) ;;
  *) fail "a settle must log the cause it retired and what it cost: $settle_msg" ;;
esac

# HISTORY IS KEPT. The ledger is an audit trail and the settle APPENDS to it —
# the lines recording the original spend must still be there, and the
# boot-scoped total they feed must be untouched, or a cross-boot credit would
# have silently financed a boot-scoped overdraft.
[ "$(wc -l < "$debt_file" | tr -d ' ')" = "$((before_lines + 1))" ] ||
  fail "a settle must APPEND one line, never rewrite the ledger"
[ "$(pd_debt_count "$debt_file")" = 3 ] ||
  fail "a settle bills zero domains and must leave the boot-scoped total alone"

# A DIFFERENT CAUSE IS UNTOUCHED. The settle names one bucket; a second
# recurring defect must keep its own running total.
pd_debt_record "$debt_file" 3 rank-start-failures "a different defect" warm-wedged
[ "$(pd_cause_total "$debt_file" peer-absent)" = 0 ] || fail "the settled bucket must stay settled"
[ "$(pd_cause_total "$debt_file" warm-wedged)" = 3 ] || fail "an unrelated bucket must keep its own running total"
printf 'warm-wedged\n' > "$latch_file"
if pd_cause_budget_ok "$latch_file"; then
  fail "settling one cause must not clear an unrelated cause's budget"
fi

# NOTHING TO SETTLE IS SILENT. The soak probe passes every recheck interval for
# the life of a healthy session; an entry per pass would bury the ledger it is
# written into.
rm -f "$latch_file" "$(halt_cause_file "$latch_file")"
before_lines="$(wc -l < "$debt_file" | tr -d ' ')"
[ -z "$(pd_cause_settle_on_evidence "$latch_file")" ] || fail "with no would-be cause a settle must say nothing"
printf 'never-halted-on-this\n' > "$latch_file"
[ -z "$(pd_cause_settle_on_evidence "$latch_file")" ] || fail "a bucket already at zero must not be re-settled"
[ "$(wc -l < "$debt_file" | tr -d ' ')" = "$before_lines" ] ||
  fail "a settle with nothing to retire must not write to the ledger"

# --- 6. THE BUDGET MUST SURVIVE THE REBOOT IT IS COUNTING -------------------
# halt_drop_if_pre_boot clears the latch on every boot. Keyed on the latch
# alone, this rung would be inert until that boot's first halt — so a cause
# already at budget would bill a fresh couple of domains every boot, forever,
# which is the leak-reboot-leak loop the whole axis exists to end.
: > "$debt_file"
rm -f "$latch_file"
halt_write "$halt_file" "$latch_file" peer-absent "a standdown, one boot ago"
[ "$(cat "$(halt_cause_file "$latch_file")")" = "peer-absent" ] \
  || fail "halt_write must record the cause outside the latch"

# The reboot: halt marker, latch and counter all go. The sibling must not.
rm -f "$halt_file" "$latch_file"
[ -f "$(halt_cause_file "$latch_file")" ] \
  || fail "the cross-boot cause record must survive the reset that clears the latch"

pd_debt_record "$debt_file" 3 rank-start-failures "spent across earlier boots" peer-absent
if pd_cause_budget_ok "$latch_file" 2> /dev/null; then
  fail "a cause at budget must refuse from tick 1 of a fresh boot, before any halt"
fi

# Under budget it passes exactly as before, so cold-boot formation is untouched.
: > "$debt_file"
pd_debt_record "$debt_file" 2 rank-start-failures "under budget" peer-absent
pd_cause_budget_ok "$latch_file" \
  || fail "an under-budget cause must still pass on a fresh boot"

# A live latch still wins over the stale sibling — the current verdict first.
printf 'warm-wedged\n' > "$latch_file"
: > "$debt_file"
pd_debt_record "$debt_file" 3 rank-start-failures "peer-absent at budget" peer-absent
pd_cause_budget_ok "$latch_file" \
  || fail "the latch is the current verdict and must be read before the sibling"
rm -f "$latch_file" "$(halt_cause_file "$latch_file")"

# 0 disables the axis, the same convention every other threshold here uses.
printf 'peer-absent\n' > "$latch_file"
CLUSTER_PD_CAUSE_BUDGET=0 pd_cause_budget_ok "$latch_file" \
  || fail "a budget of 0 must disable the axis"

echo "PASS: peer-armed handshake gate, auto re-arm, and cause-keyed PD budget"
