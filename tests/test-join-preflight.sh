#!/usr/bin/env bash
# THE CHECK THAT FAILS IF cluster-join CAN AGAIN SPEND TEN MINUTES AND THEN BLAME
# THE WRONG MACHINE.
#
# On 2026-08-01 the worker's cluster-join waited the full 600s and the rank died
# with:
#
#   RuntimeError: [jaccl] Couldn't connect (error: 60)
#
# errno 60 is ETIMEDOUT. It reports that a connection did not complete and is
# structurally incapable of saying why — and the why was on the OTHER machine:
# the coordinator had the identical generation drift and held no link address, so
# there was never anything to rendezvous with. Ten minutes of waiting produced
# one number that pointed at neither cause nor host.
#
# Two things are pinned here:
#   1. peer_link_preflight — the bounded probe that now runs BEFORE the long
#      wait, so an absent peer costs ~2 minutes instead of ~10 and no rank is
#      started (hence no RDMA protection domain is spent on a certain failure).
#   2. generation_parity_fact — the single definition of the parity comparison,
#      now shared with the link watcher. Two copies would be two answers, and the
#      watcher's copy is the one that has to run unattended.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — peer_link_preflight, peer_reachable and generation_parity_fact are
#           sourced from the shipped layers.
#   STUB  — ping through CLUSTER_PING_BIN, darwin-version through
#           CLUSTER_DARWIN_VERSION_BIN, git through CLUSTER_GIT_BIN (the same
#           seam idiom as CLUSTER_NETSTAT_BIN); plus date and sleep, so the
#           timeout is asserted by the deadline it COMPUTES rather than waited
#           out.
#   PIN   — cluster-join.sh's own call sites, as source. A correct function
#           nobody calls passes every behavioural assertion while the defect is
#           fully back.
#
# Usage:
#   PROBE=/path/to/cluster-peer-probe.sh \
#   PREFLIGHT=/path/to/cluster-join-preflight.sh \
#   PARITY=/path/to/cluster-generation-parity.sh \
#   JOIN=/path/to/cluster-join.sh bash test-join-preflight.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# RFC 5737 documentation address: this test never touches a real link.
export CLUSTER_STATIC_PEER_IP=192.0.2.1

# shellcheck disable=SC1090
source "${PROBE:?set PROBE to the path of cluster-peer-probe.sh}"
# shellcheck disable=SC1090
source "${PREFLIGHT:?set PREFLIGHT to the path of cluster-join-preflight.sh}"
# shellcheck disable=SC1090
source "${PARITY:?set PARITY to the path of cluster-generation-parity.sh}"

shebang="#!$BASH"
mkdir -p "$tmp/bin"

# ping, through the seam the shipped probe already reads. Answers only while the
# marker exists, and records every invocation so "did it actually probe?" is a
# fact rather than an assumption.
{
  printf '%s\n' "$shebang"
  cat << 'FAKE'
printf '%s\n' "$*" >> "$FAKE_DIR/ping.log"
[ -f "$FAKE_DIR/peer-up" ]
FAKE
} > "$tmp/bin/ping"
chmod +x "$tmp/bin/ping"
export CLUSTER_PING_BIN="$tmp/bin/ping"
export FAKE_DIR="$tmp"

# Clock and sleep, so the bound is asserted by the deadline the function computes
# and the test does not actually wait two minutes. Only `date +%s` is
# intercepted; every other format defers to the real binary.
now=0
slept_total=0
date() {
  case "${1:-}" in
    +%s) echo "$now" ;;
    *) command date "$@" ;;
  esac
}
sleep() {
  slept_total=$((slept_total + $1))
  now=$((now + $1))
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
pings() { grep -c . "$tmp/ping.log" 2> /dev/null || true; }
reset_state() {
  : > "$tmp/ping.log"
  rm -f "$tmp/peer-up"
  now=0
  slept_total=0
}

echo "stub contract (the preflight reaches ping only through this):"
reset_state
peer_reachable && up=0 || up=1
check "peer_reachable false while the peer is absent" 1 "$up"
touch "$tmp/peer-up"
peer_reachable && up=0 || up=1
check "peer_reachable true once the peer answers" 0 "$up"
check "and it really invoked the probe" 2 "$(pings)"

echo
echo "a peer that is already up costs one probe and no wait:"
reset_state
touch "$tmp/peer-up"
export CLUSTER_PEER_READY_TIMEOUT_SECS=120
export CLUSTER_PEER_READY_POLL_SECS=5
peer_link_preflight && ok=0 || ok=1
check "preflight passes" 0 "$ok"
check "one probe" 1 "$(pings)"
check "no waiting" 0 "$slept_total"

echo
echo "a peer that arrives late is waited for, not refused:"
# Both watchers now self-heal their own link prep, so a peer that is merely a
# tick or two behind must still be picked up.
reset_state
export CLUSTER_PEER_READY_TIMEOUT_SECS=120
export CLUSTER_PEER_READY_POLL_SECS=5
# The stub's answer is a marker file; create it after the third probe by
# arranging for the poll to make it appear.
sleep() {
  slept_total=$((slept_total + $1))
  now=$((now + $1))
  [ "$slept_total" -ge 15 ] && touch "$tmp/peer-up"
  return 0
}
peer_link_preflight && ok=0 || ok=1
check "preflight passes once the peer answers" 0 "$ok"
check "waited only as long as it took" 15 "$slept_total"

echo
echo "THE DEFECT: an absent peer is refused at the SHORT bound, not the long one:"
# Without this, an unprepared peer cost joinTimeoutSecs (600s) and then produced
# a raw errno about the wrong machine.
reset_state
sleep() {
  slept_total=$((slept_total + $1))
  now=$((now + $1))
}
export CLUSTER_PEER_READY_TIMEOUT_SECS=120
export CLUSTER_PEER_READY_POLL_SECS=5
peer_link_preflight && ok=0 || ok=1
check "preflight refuses" 1 "$ok"
check "and gave up at its own bound, nowhere near 600s" 120 "$slept_total"

echo
echo "the bound is configurable and honoured:"
reset_state
export CLUSTER_PEER_READY_TIMEOUT_SECS=30
export CLUSTER_PEER_READY_POLL_SECS=10
peer_link_preflight && ok=0 || ok=1
check "preflight refuses" 1 "$ok"
check "waited the configured bound" 30 "$slept_total"

echo
echo "generation parity: ONE comparison, five states, no inference by the caller:"
# The watcher reads this on a timer and cluster-join reads it before a join. A
# second copy of the comparison would be a second answer.
# $1 = the revision this system generation is stamped with ("" = a dirty or
# unstamped build, which emits no configurationRevision at all).
# $2 = the deploy branch HEAD ("" = the remote is unreachable).
parity_stub() {
  local local_rev="$1" remote_rev="$2" json='{}'
  [ -n "$local_rev" ] && json="{\"configurationRevision\":\"$local_rev\"}"
  {
    printf '%s\n' "$shebang"
    printf 'echo %s\n' "'$json'"
  } > "$tmp/bin/darwin-version"
  chmod +x "$tmp/bin/darwin-version"
  {
    printf '%s\n' "$shebang"
    if [ -n "$remote_rev" ]; then
      printf 'printf "%s\\trefs/heads/main\\n"\n' "$remote_rev"
    else
      printf 'exit 128\n'
    fi
  } > "$tmp/bin/git"
  chmod +x "$tmp/bin/git"
}
export CLUSTER_DARWIN_VERSION_BIN="$tmp/bin/darwin-version"
export CLUSTER_GIT_BIN="$tmp/bin/git"
export CLUSTER_GENERATION_REPO=example/deploy

parity_stub aaaaaaaaaaaa aaaaaaaaaaaa
check "matching revisions are ok" "state=ok local=aaaaaaaaaaaa deploy=aaaaaaaaaaaa" \
  "$(generation_parity_fact)"
parity_stub aaaaaaaaaaaa bbbbbbbbbbbb
check "differing revisions are drift" "state=drift local=aaaaaaaaaaaa deploy=bbbbbbbbbbbb" \
  "$(generation_parity_fact)"
parity_stub "" bbbbbbbbbbbb
check "a dirty/unstamped build is unstamped, never ok" "state=unstamped local= deploy=bbbbbbbbbbbb" \
  "$(generation_parity_fact)"
parity_stub aaaaaaaaaaaa ""
check "an unreachable deploy branch is unverified, never drift" \
  "state=unverified local=aaaaaaaaaaaa deploy=" "$(generation_parity_fact)"
CLUSTER_GENERATION_REPO=""
check "no repo configured disables the check explicitly" "state=disabled local= deploy=" \
  "$(generation_parity_fact)"
CLUSTER_GENERATION_REPO=example/deploy

echo
echo "call sites in cluster-join.sh (a function nobody calls fixes nothing):"
join="${JOIN:?set JOIN to the path of cluster-join.sh}"
# Code lines only: the comments legitimately quote the old behaviour.
code() { grep -v '^[[:space:]]*#' "$join"; }
pin() {
  local label="$1" pattern="$2"
  if code | grep -Eq "$pattern"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/"
    fail=1
  fi
}
anti_pin() {
  local label="$1" pattern="$2"
  if code | grep -Eq "$pattern"; then
    echo "  FAIL $label -> code line matching /$pattern/ is back"
    fail=1
  else
    echo "  ok   $label"
  fi
}
pin "join uses the SHARED parity comparison" '(^|[^_[:alnum:]])generation_parity_fact'
anti_pin "join no longer carries its own copy of the ls-remote comparison" 'git ls-remote'
anti_pin "join no longer reads darwin-version itself" 'darwin-version --json'
pin "join runs the peer preflight" '(^|[^_[:alnum:]])peer_link_preflight'
pin "a missing peer is a hard failure naming the unverified side" \
  'fail "peer unreachable at the rendezvous address'
# The preflight has to come BEFORE the block-until-serving wait, or it saves
# nothing: line order is the property under test, so it is asserted as such.
preflight_line="$(grep -n 'peer_link_preflight' "$join" | head -n1 | cut -d: -f1)"
wait_line="$(grep -n 'CLUSTER_JOIN_TIMEOUT_SECS' "$join" | tail -n1 | cut -d: -f1)"
if [ -n "$preflight_line" ] && [ -n "$wait_line" ] && [ "$preflight_line" -lt "$wait_line" ]; then
  echo "  ok   the preflight runs before the block-until-serving wait"
else
  echo "  FAIL preflight (line ${preflight_line:-none}) must precede the long wait (line ${wait_line:-none})"
  fail=1
fi

exit "$fail"
