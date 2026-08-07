#!/usr/bin/env bash
# peer_rendezvous_session — the predicate the pair-wide standdown trusts.
#
# It answers "is the peer's rank process still there?" from netstat alone, with no
# SSH between nodes. Absence is an accepted teardown trigger because session
# persistence across a full generation is MEASURED (24 of 24 samples ESTABLISHED
# across a 1000-token / 38.9s generation on the live cluster), so a false negative
# here tears down a healthy rank mid-generation.
#
# THE BUG THIS EXISTS TO PREVENT: netstat prints the port BEFORE the state,
#   tcp4  0  0  192.168.208.1.11441  192.168.208.2.49223  ESTABLISHED
# so an ad-hoc `grep 'ESTABLISHED.*\.11441'` matches NOTHING and reports a healthy
# serving cluster as dead. That exact probe was used by hand and returned 0 for 25
# consecutive samples while the cluster was serving. The shipped predicate uses
# order-independent index() and must stay that way.
#
# REAL — peer_rendezvous_session, sourced from the shipped helpers.
# STUB — netstat, via the CLUSTER_NETSTAT_BIN seam the function already exposes.
#
# Usage:
#   HELPERS=/path/to/cluster-link-helpers.sh bash test-peer-rendezvous-session.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
export CLUSTER_STATE_FILE="$state_dir/link-state"

# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to the path of cluster-link-helpers.sh}"

export CLUSTER_STATIC_PEER_IP=192.168.208.2
export CLUSTER_RENDEZVOUS_PORT=11441

# The netstat seam. A shell FUNCTION, not a generated script: the nix build sandbox
# has no /usr/bin/env, so a shebang stub silently fails to execute and every case
# reports "absent" — which passes the absent assertions and fails only the present
# ones. That asymmetry is exactly how this was caught in CI. A function is
# invoked by name through the same seam and needs no interpreter on disk.
netstat_rows=""
fake_netstat() { printf '%s\n' "$netstat_rows"; }
export CLUSTER_NETSTAT_BIN=fake_netstat
set_netstat() { netstat_rows="$1"; }

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
present() { peer_rendezvous_session && echo present || echo absent; }

echo "real netstat layout (port BEFORE state) is detected:"
# Verbatim shape from the live cluster. This is the case the ad-hoc grep missed.
set_netstat 'Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp4       0      0  192.168.208.1.11441    192.168.208.2.49223    ESTABLISHED'
check "session seen when the row is real netstat order" present "$(present)"

echo "order independence (state before port) also matches:"
set_netstat 'tcp4  0  0  ESTABLISHED  192.168.208.2.49223  192.168.208.1.11441'
check "session seen regardless of field order" present "$(present)"

echo "absence is reported when the peer is gone:"
set_netstat 'Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp4       0      0  192.168.208.1.11441    *.*                    LISTEN'
check "listening-only is NOT a session" absent "$(present)"

echo "a half-closed session after peer death reads as ABSENT:"
# Observed when the worker rank was SIGKILLed: ESTABLISHED -> CLOSE_WAIT. If
# CLOSE_WAIT counted as present, a dead peer would never be detected.
set_netstat 'tcp4  0  0  192.168.208.1.11441  192.168.208.2.49223  CLOSE_WAIT'
check "CLOSE_WAIT is not a live session" absent "$(present)"

echo "a session to a DIFFERENT port is not the rendezvous:"
set_netstat 'tcp4  0  0  192.168.208.1.11440  192.168.208.2.49223  ESTABLISHED'
check "endpoint-port session is ignored" absent "$(present)"

echo "a session with a DIFFERENT peer is not ours:"
set_netstat 'tcp4  0  0  192.168.208.1.11441  10.0.0.9.49223  ESTABLISHED'
check "other-peer session is ignored" absent "$(present)"

echo "no rendezvous port configured means no claim:"
set_netstat 'tcp4  0  0  192.168.208.1.11441  192.168.208.2.49223  ESTABLISHED'
saved="$CLUSTER_RENDEZVOUS_PORT"
unset CLUSTER_RENDEZVOUS_PORT
check "unset port reports absent rather than guessing" absent "$(present)"
export CLUSTER_RENDEZVOUS_PORT="$saved"

echo "an unreadable netstat reports absent, never a false present:"
export CLUSTER_NETSTAT_BIN="$state_dir/does-not-exist"
check "missing netstat binary reports absent" absent "$(present)"
export CLUSTER_NETSTAT_BIN=fake_netstat

echo "the stub itself is exercised (guards against a silently dead stub):"
# The whole suite would pass vacuously if the stub produced nothing: every case
# would read "absent", and only the two present-cases would notice. Assert the
# seam directly so a dead stub fails loudly instead of hiding.
set_netstat 'tcp4  0  0  192.168.208.1.11441  192.168.208.2.49223  ESTABLISHED'
check "stub emits the row it was given" 1 "$(fake_netstat -an -p tcp | grep -c ESTABLISHED)"

# --- Source pins on the teardown this predicate feeds -------------------------
#
# The predicate above is only half the contract. What it triggers is the
# pair-wide standdown, and that block deletes its own strike counter — so
# without a halt marker nothing suppresses the next kickstart: the rank
# restarts, settles, re-strikes, and stands down again forever. Measured on the
# coordinator with the Thunderbolt cable out: 560 standdowns between 2026-07-12
# and 2026-08-05, each one kickstarting the warmup agent and holding
# llama-swap's single concurrency slot.
#
# Pinned by source inspection rather than executed, for the reason
# tests/test-pd-guard-integrity.sh states plainly: the block is inline in a
# script that calls launchctl, sysctl and curl at import time, so it cannot be
# sourced in the build sandbox. These pins prove the call SITE exists and is
# ordered correctly; they do not simulate a standdown.
echo "the pair-wide standdown writes a halt so it cannot loop:"
watcher="${WATCHER:?WATCHER is required}"
# Code lines only — the comments around this block legitimately describe the
# uncapped behaviour being replaced, and a prose-matching scan would pass on
# its own changelog.
code() { grep -vE '^[[:space:]]*#' "$watcher"; }

# Ordering is the whole point: a halt written AFTER the kill is a halt the next
# tick's kickstart has already raced past.
halt_line="$(grep -n 'halt_write .* "peer-absent"' "$watcher" | head -1 | cut -d: -f1)"
kill_line="$(awk -v start="${halt_line:-0}" 'NR > start && /launchctl kill SIGTERM/ { print NR; exit }' "$watcher")"
check "the halt precedes its SIGTERM" yes \
  "$([ -n "$halt_line" ] && [ -n "$kill_line" ] && [ "$halt_line" -lt "$kill_line" ] && echo yes || echo no)"

# Every teardown that means "this rank cannot work" must halt, so none of them
# can loop the way peer-absent did. Pinned by CAUSE rather than by count: a bare
# total breaks the moment a legitimate fourth teardown is added, which trains
# the next person to bump the number instead of reading the assertion.
#
# Deliberately NOT pinned: the readiness probe also sends SIGTERM but does not
# halt, because that path is a restart-on-hung-init that is SUPPOSED to retry.
# A blanket "every SIGTERM halts" rule would be wrong and would break it.
for cause in peer-absent health-gate-fail health-gate-soak-fail rank-start-failures; do
  check "the $cause teardown halts" 1 \
    "$(code | grep -c "halt_write .* \"$cause\"" || true)"
done

exit "$fail"
