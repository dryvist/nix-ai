# shellcheck shell=bash
# Cluster link watcher — rank-start guards and the halt latch.
#
# Function definitions ONLY (no top-level statements), concatenated ahead of
# cluster-link-watcher.sh with cluster-link-helpers.sh,
# cluster-link-locate.sh and cluster-link-repair.sh. Marker paths are passed as
# ARGUMENTS rather than read from the watcher's scope, so each function is
# callable — and testable — on its own.
#
# WHY THIS FILE EXISTS. Start order is load-bearing and until 2026-07-25 nothing
# enforced it. Each host's watcher converges independently, so a worker whose
# coordinator has no rank yet will kickstart into a rendezvous that does not
# exist:
#
#   RuntimeError: [jaccl] Couldn't connect (error: 60)   # errno 60 = ETIMEDOUT
#   ... 3 attempts, PD guard HALTS ...
#   ValueError: [jaccl] Changing queue pair to RTR failed with errno 96
#
# Every failed mx.distributed.init() leaks a kernel RDMA Protection Domain and
# exhaustion is reboot-only. A worker hammering an absent peer therefore converts
# a trivially recoverable situation (peer not up yet — wait) into a mandatory
# reboot. It did exactly that on 2026-07-24.
#
# Consumed environment:
#   CLUSTER_ROLE                     coordinator | worker
#   CLUSTER_STATIC_PEER_IP           peer's link address; for a worker the peer
#                                  IS the coordinator, which is why the
#                                  rendezvous probe needs no second address
#   CLUSTER_RENDEZVOUS_PORT          JACCL rendezvous port (MLX_JACCL_COORDINATOR)
#   CLUSTER_PEER_PROBE_TIMEOUT_SECS  bound on the rendezvous TCP connect
#   CLUSTER_LINK_REPAIR              1 = attempt link-prep repair when this
#                                  host holds no link address
#   CLUSTER_LINK_ACTIVATE_TIMEOUT_SECS  bound on the activation repair fallback
#   CLUSTER_WIRED_LIMIT_MB           optional cluster wired ceiling

# Unattended repair for a host that came up WITHOUT its link address.
#
# A boot does not produce a usable link. nix-darwin's cluster-link prep runs in
# root postActivation, which fires before Thunderbolt carrier settles, so the
# prep pass can find no carrier-active port and therefore address nothing —
# observed 2026-07-24 on the coordinator: en2 had carrier, activation had run,
# and no interface held the link address at all. Re-running `activate` fixed it
# and logged `[cluster-link-prep] set <ip> on en2 (carrier active)`. The rank
# started in that window died with `[jaccl] Couldn't bind socket (error: 49)` —
# errno 49 is EADDRNOTAVAIL, i.e. exactly this missing address.
#
# Direct repair goes FIRST here (unlike cluster-join, which prefers activation
# for persistence): this runs on a 30s watcher tick, and the direct grant is the
# same ifconfig alias the prep pass would apply, without a full activation's
# blast radius. Activation is the bounded fallback.
repair_link_prep() {
  local activate_timeout="${CLUSTER_LINK_ACTIVATE_TIMEOUT_SECS:-0}"
  echo "cluster-link: repairing link prep ($CLUSTER_STATIC_SELF_IP absent; direct granted alias)"
  repair_link_direct || true
  if link_prep_ok; then
    echo "cluster-link: link prep repaired ($CLUSTER_STATIC_SELF_IP on $(iface_holding_self_ip))"
    return 0
  fi
  if [ "$activate_timeout" -gt 0 ]; then
    echo "cluster-link: direct repair did not restore prep; re-running activation (bounded ${activate_timeout}s)"
    timeout "$activate_timeout" sudo -n /nix/var/nix/profiles/system/activate > /dev/null 2>&1 || true
    if link_prep_ok; then
      echo "cluster-link: link prep repaired by activation ($CLUSTER_STATIC_SELF_IP on $(iface_holding_self_ip))"
      return 0
    fi
  fi
  echo "cluster-link: WARN link prep still broken; $CLUSTER_STATIC_SELF_IP is on no carrier-active Thunderbolt port outside bridge0. Is the cable seated?" >&2
  return 1
}

# Is rank 0 actually listening on the JACCL rendezvous port? A plain TCP connect,
# because that is precisely what mx.distributed.init() does next — and when the
# answer is "no", init burns a protection domain to find out.
#
# Bounded by coreutils `timeout`, not by nc's own flags: Apple's nc takes -w but
# applies it to idle reads, NOT to connect setup — measured 2026-07-25, a
# blackholed SYN with `-w 2` still took 75s (the kernel's SYN budget), while
# `timeout 2 nc -z` returned at 2.01s. A probe that can outlive the 30s watcher
# tick is not a probe. Verified on macOS the same day: listening -> rc 0,
# closed port -> rc 1 in 4ms, blackhole -> rc 124 at the bound.
peer_rendezvous_listening() {
  local host="$1" port="$2" secs="${3:-2}"
  timeout "$secs" /usr/bin/nc -z "$host" "$port" > /dev/null 2>&1
}

# Everything that must hold before a rank start is allowed to CONSUME a start
# attempt. Nonzero return = do not start, do not count it.
#
# "Do not count it" is the whole point, and there is precedent: the wired-ceiling
# check (folded in below, rung 3) has always skipped the start without consuming
# an attempt. A precondition that is not yet satisfied is not a failed start —
# it leaks no protection domain — so counting it would spend the PD guard's
# budget on a situation that costs nothing, and the guard's budget is the thing
# standing between a missing peer and a forced reboot.
#
# Sets PRECONDITION_REASON to a stable cause token for the halt marker.
rank_start_preconditions_ok() {
  PRECONDITION_REASON=""
  # 1. This host must hold its own link address. A boot does not guarantee one
  #    (see repair_link_prep): the rank would die with errno 49 EADDRNOTAVAIL.
  if ! link_prep_ok; then
    PRECONDITION_REASON="link-address-missing"
    echo "cluster-link: this host holds no carrier-active link address; NOT starting the rank (no attempt consumed)" >&2
    if [ "${CLUSTER_LINK_REPAIR:-1}" = "1" ]; then
      repair_link_prep || true
    fi
    return 1
  fi
  # 2. WORKER ONLY: rank 0 must already be listening. The coordinator has no
  #    such precondition — it is the one that must come up first, and gating it
  #    on the worker would deadlock the cluster into mutual waiting.
  if [ "$CLUSTER_ROLE" != "coordinator" ]; then
    if ! peer_rendezvous_listening "$CLUSTER_STATIC_PEER_IP" \
      "${CLUSTER_RENDEZVOUS_PORT:?CLUSTER_RENDEZVOUS_PORT is required}" \
      "${CLUSTER_PEER_PROBE_TIMEOUT_SECS:-2}"; then
      PRECONDITION_REASON="peer-rendezvous-absent"
      echo "cluster-link: rank 0 is not listening on $CLUSTER_STATIC_PEER_IP:$CLUSTER_RENDEZVOUS_PORT; waiting for the coordinator (NOT starting the rank, no attempt consumed)"
      return 1
    fi
  fi
  # 3. Never start a rank over a standalone-sized ceiling: a shard wiring out
  #    the GUI working set is the 2026-07-12 dual-host panic.
  if ! set_wired_limit "${CLUSTER_WIRED_LIMIT_MB:-}"; then
    PRECONDITION_REASON="wired-ceiling"
    echo "cluster-link: wired ceiling not applied; NOT starting the rank (no attempt consumed)"
    return 1
  fi
  return 0
}

# Decide whether a by-hand clear of the halt marker may stand.
#
# On 2026-07-24 the PD guard fired correctly at three consecutive failures, and a
# human then deleted the marker to force a retry on an unverified hypothesis —
# burning the remaining protection domains and making the reboot mandatory. The
# design invited it: the halt was just a file, and the docs said "rm the marker
# or replug".
#
# So a clear is now a REQUEST, not a fact. It stands only if the preconditions
# actually pass; otherwise the halt is rewritten and the operator is told which
# cause is still failing. Accepting a clear also resets the attempt counter,
# because leaving it at the cap would re-halt on the very next tick and make the
# documented recovery a no-op.
#
# $1 halt marker, $2 latch, $3 kickstart counter. 0 = clear accepted.
halt_clear_accepted() {
  local halt_file="$1" latch_file="$2" kicks_file="$3" prior
  prior="$(cat "$latch_file" 2> /dev/null || echo unknown)"
  if rank_start_preconditions_ok; then
    echo "cluster-link: halt marker cleared by hand and preconditions RE-VERIFIED (prior cause: $prior); allowing one retry"
    rm -f "$latch_file" "$kicks_file"
    return 0
  fi
  echo "cluster-link: halt marker cleared by hand but preconditions still fail ($PRECONDITION_REASON); RE-HALTING — a manual clear must not re-burn RDMA protection domains" >&2
  halt_write "$halt_file" "$latch_file" "manual-clear-rejected" \
    "prior=$prior still-failing=$PRECONDITION_REASON"
  return 1
}
