# shellcheck shell=bash
# cluster-join — peer link preflight.
#
# WHY. On 2026-08-01 the worker's cluster-join waited the FULL 600s and then the
# rank died with:
#
#   RuntimeError: [jaccl] Couldn't connect (error: 60)
#
# The cause was on the OTHER machine — the coordinator had the identical
# generation drift and held no link address, so there was never anything to
# rendezvous with. Nothing in the ten minutes of waiting, and nothing in the
# error, said which side was unprepared. errno 60 is ETIMEDOUT: it reports that
# a connection did not complete, and is structurally incapable of saying why.
#
# So: establish whether there is a prepared peer BEFORE spending the long wait,
# and when there is not, say which side is which. This side's prep has already
# been verified (and repaired) by step 1, so an unanswered peer address with a
# healthy local link is attributable — not to a diagnosis, but to a boundary:
# everything this host owns is good, and the peer is not answering.
#
# It cannot claim the peer's link prep is broken, and deliberately does not: the
# link address is the only channel to the peer, so when it is silent the peer's
# prep is UNVERIFIED, not failed. Saying "unverified" is the honest form and it
# is still enough to send someone to the right machine.
#
# Function definitions ONLY; concatenated into cluster-join with
# ./cluster-peer-probe.sh, which owns peer_reachable (shared with the watcher and
# the peer-liveness supervisor — one definition of "is the peer there").
#
# Consumed environment:
#   CLUSTER_STATIC_PEER_IP        peer's link address
#   CLUSTER_PEER_READY_TIMEOUT_SECS  bound on this wait
#   CLUSTER_PEER_READY_POLL_SECS     seconds between probes

# Wait, briefly, for the peer to answer on the link. 0 = a peer is there.
#
# The bound is short on purpose. Both watchers now self-heal their own link prep
# unattended, so a peer that is merely slow answers within a tick or two; one
# that is still silent after this window is not "about to arrive", it is
# unprepared — and finding that out in two minutes rather than ten is the whole
# point. A join that returns early costs a re-run; a join that blocks for the
# full timeout costs ten minutes and then reports a raw errno about the wrong
# machine.
peer_link_preflight() {
  local timeout_secs="${CLUSTER_PEER_READY_TIMEOUT_SECS:-120}"
  local poll="${CLUSTER_PEER_READY_POLL_SECS:-5}"
  local deadline
  deadline=$(($(date +%s) + timeout_secs))
  while :; do
    if peer_reachable; then
      return 0
    fi
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep "$poll"
  done
}
