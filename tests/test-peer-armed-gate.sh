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
#          current_boot_epoch, and mem_headroom_ok, which reads vm_stat and so
#          cannot run on the Linux CI runner.
#
# Peer address is an RFC 5737 documentation address, never a real link address.
#
# Usage:
#   BOOT_SCOPE=... LEDGER=... CAUSE=... RECORD=... PEER_STATE=... \
#     bash test-peer-armed-gate.sh
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

# A halt is the state the peer most needs to see, so it must still publish.
printf '%s\tcause=peer-absent\tboot=1785031601\tdetail\n' "2026-08-08T00:00:00Z" > "$halt_file"
peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file"
[ "$(jq -r '.armed' "$published")" = "false" ] || fail "a halted host must publish armed=false"
[ "$(jq -r '.halted_cause' "$published")" = "peer-absent" ] \
  || fail "a halted host must publish the cause it halted on"
rm -f "$halt_file"

# Generation drift disarms, because a mixed mlx/JACCL stack cannot mesh.
peer_state_write "$published" "state=drift local=abc123 deploy=def456" "$halt_file" "$debt_file"
[ "$(jq -r '.armed' "$published")" = "false" ] || fail "a drifted host must publish armed=false"

# No memory headroom disarms AND is reported separately, because its remedy
# (a reboot, to return unreclaimed wired Metal) differs from every other term.
mem_ok=1
peer_state_write "$published" "$ok_parity" "$halt_file" "$debt_file"
[ "$(jq -r '.wired_ok' "$published")" = "false" ] || fail "no headroom must publish wired_ok=false"
[ "$(jq -r '.armed' "$published")" = "false" ] || fail "no headroom must also disarm"
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

# --- 5. the budget, and the ONLY thing that clears it -----------------------
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

# No latch = no would-be cause = nothing to refuse.
rm -f "$latch_file"
pd_cause_budget_ok "$latch_file" || fail "with no halt latch there is no cause to refuse"

# 0 disables the axis, the same convention every other threshold here uses.
printf 'peer-absent\n' > "$latch_file"
CLUSTER_PD_CAUSE_BUDGET=0 pd_cause_budget_ok "$latch_file" \
  || fail "a budget of 0 must disable the axis"

echo "PASS: peer-armed handshake gate, auto re-arm, and cause-keyed PD budget"
