# shellcheck shell=bash
# Is the peer host answering on the cluster link at all?
#
# ONE definition, three consumers: the link watcher's start guards, the
# peer-liveness supervisor, and cluster-join's peer preflight. It lived in
# ./cluster-link-helpers.sh until cluster-join needed it too — and join gets none
# of the serving helpers around it, so a shared function had to become its own
# layer rather than a second copy. writeShellApplication runs shellcheck at
# default severity, where a function shipped to a consumer that never calls it is
# an SC2329 build failure, which is what keeps these layers honest.
#
# Deliberately a HOST liveness probe, never a "is rank 0 listening" probe. The
# latter was removed on 2026-07-25 because waiting on the peer's PROCESS forced
# the two ranks into a sequence jaccl's ~15s connect budget cannot absorb. Host
# reachability carries none of that hazard: it does not order the ranks, it only
# establishes that there is a peer to rendezvous WITH.
#
# Consumed environment:
#   CLUSTER_STATIC_PEER_IP  peer's static link address
#   CLUSTER_PING_BIN        ping path (test seam; /sbin is not on a
#                         writeShellApplication PATH)
peer_reachable() {
  "${CLUSTER_PING_BIN:-/sbin/ping}" -c 3 -t 2 -q "${CLUSTER_STATIC_PEER_IP}" > /dev/null 2>&1
}
