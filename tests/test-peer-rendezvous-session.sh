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

# The netstat seam: a script whose output we control per case.
fake_netstat="$state_dir/netstat"
export CLUSTER_NETSTAT_BIN="$fake_netstat"
set_netstat() {
  printf '#!/usr/bin/env bash\ncat <<'\''ROWS'\''\n%s\nROWS\n' "$1" > "$fake_netstat"
  chmod +x "$fake_netstat"
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
export CLUSTER_NETSTAT_BIN="$fake_netstat"

exit "$fail"
