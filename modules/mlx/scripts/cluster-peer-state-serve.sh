# shellcheck shell=bash
# Cluster peer state — the responder.
#
# Serves the JSON line the link watcher publishes each tick
# (peer_state_write in ./cluster-peer-state.sh) to the host on the other end of
# the Thunderbolt cable, so that host can decide whether starting its rank has
# any chance of rendezvousing before it spends an RDMA protection domain
# finding out.
#
# DUMB TRANSPORT, ON PURPOSE. It computes nothing, reads no marker, and shares
# no function with the rest of the cluster scripts — it cats a file. Every fact
# it serves is derived once, in the watcher, by the same code that acts on those
# facts locally, so the two sides of the pair cannot disagree about what
# "armed" means. A responder that recomputed state would be a second
# implementation of the most safety-critical predicate in the subsystem.
#
# WHY nc AND NOT A REAL SERVER. The payload is one line, the client is one
# `curl -m 2` on a point-to-point cable, and the whole contract is "return the
# current contents of this file". The alternatives all cost more than they
# return: a python http.server is a resident interpreter for a static file,
# and launchd socket activation (Sockets + inetdCompatibility) would have
# launchd bind the address — which does not exist until the cable is in and
# activation has aliased it, making the failure mode a throttled agent rather
# than a retry loop we control.
#
# BOUND TO THE LINK ADDRESS ONLY, never 0.0.0.0. The state names this host's
# system generation and its halt causes; it belongs on the cable and nowhere
# else. That address is absent until the Thunderbolt port has carrier and
# nix-darwin's link prep has aliased it, so a failed bind is the NORMAL state of
# an unplugged machine — hence the retry loop rather than an exit.
#
# Consumed environment:
#   CLUSTER_PEER_STATE_FILE         the published line (written by the watcher)
#   CLUSTER_PEER_STATE_PORT         port to listen on
#   CLUSTER_STATIC_SELF_IP          this host's link address — the only bind
#   CLUSTER_PEER_STATE_RETRY_SECS   pause after a failed bind (cable out)
#   CLUSTER_NC_BIN                  nc path (test seam; /usr/bin is not on a
#                                   writeShellApplication PATH)

: "${CLUSTER_PEER_STATE_FILE:?peer state file is required}"
: "${CLUSTER_PEER_STATE_PORT:?peer state port is required}"
: "${CLUSTER_STATIC_SELF_IP:?static self ip is required}"

nc_bin="${CLUSTER_NC_BIN:-/usr/bin/nc}"
retry_secs="${CLUSTER_PEER_STATE_RETRY_SECS:-5}"

# What a peer reads before this host's watcher has ticked even once — after a
# reboot, or while the agent is starting. Not armed, and stamped ts=0 so the
# reader's staleness rung refuses it on its own terms rather than relying on
# this text. Never an empty body: an empty response is indistinguishable from a
# network failure, and the two deserve different log lines on the other side.
unpublished='{"armed":false,"halted_cause":"state-unpublished","boot":0,"wired_ok":false,"generation":"","ts":0}'

echo "cluster-peer-state: serving $CLUSTER_PEER_STATE_FILE on $CLUSTER_STATIC_SELF_IP:$CLUSTER_PEER_STATE_PORT"

while :; do
  body="$unpublished"
  if [ -f "$CLUSTER_PEER_STATE_FILE" ]; then
    body="$(cat "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || printf '%s' "$unpublished")"
  fi
  [ -n "$body" ] || body="$unpublished"
  # Content-Length and Connection: close so the client finishes the read the
  # instant the body arrives, instead of waiting on a half-closed socket that
  # Apple's nc does not shut down on stdin EOF. -w bounds a client that connects
  # and then says nothing, so one rude peer cannot hold the only listener.
  if printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
    "${#body}" "$body" |
    "$nc_bin" -l -w "${CLUSTER_PEER_STATE_TIMEOUT_SECS:-5}" \
      "$CLUSTER_STATIC_SELF_IP" "$CLUSTER_PEER_STATE_PORT" > /dev/null 2>&1; then
    # ponytail: one listener, one request at a time, with a 200ms floor between
    # accepts. Serving is single-digit milliseconds against a peer that polls
    # every 30s, so the floor only ever bounds a pathological nc that returns
    # immediately without a connection — it is a spin guard, not a rate limit.
    # Upgrade path if a second reader ever appears: launchd socket activation.
    sleep 0.2
  else
    # Almost always the cable being out, so the bind address does not exist.
    # Deliberately quiet — this is the steady state of an unplugged machine, and
    # the watcher's own link-facts reporting already says so once per change.
    sleep "$retry_secs"
  fi
done
