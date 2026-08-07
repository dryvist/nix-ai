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
#   CLUSTER_RDMA_DEVICE           configured fallback RDMA device (clusterMode.rdmaDevice),
#                                already carries the "rdma_" prefix — see rdmaDevice's default
#   CLUSTER_PD_DEVICE_BUDGET      measured max_pd this host's config assumes (see #1442)
#   CLUSTER_IBV_DEVINFO_BIN       ibv_devinfo path/seam, default /usr/bin/ibv_devinfo

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

# The carrier-active Thunderbolt port's RDMA device (e.g. "rdma_en2"), same
# discovery cluster-rank-launch.sh uses for the ibv matrix — never a pinned
# name, because moving the cable moves the port. Falls back to
# CLUSTER_RDMA_DEVICE (already prefixed) when no carrier-active port has a
# matching rdma_<dev>. Duplicated from cluster-link-guards.sh (watcher-only)
# because this file's layer (join) does not include that one — see
# cluster-script-layers.nix's per-layer function ownership.
active_rdma_device() {
  local dev
  while read -r dev; do
    [ -n "$dev" ] || continue
    /sbin/ifconfig "$dev" 2>/dev/null | /usr/bin/grep -q 'status: active' || continue
    if /usr/bin/ibv_devices 2>/dev/null | /usr/bin/awk '{print $1}' | /usr/bin/grep -qx "rdma_$dev"; then
      printf 'rdma_%s\n' "$dev"
      return 0
    fi
  done < <(
    /usr/sbin/networksetup -listallhardwareports 2>/dev/null |
      /usr/bin/awk '/^Hardware Port: Thunderbolt [0-9]/ { tb = 1; next }
           /^Device:/ { if (tb) print $2; tb = 0 }'
  )
  [ -n "${CLUSTER_RDMA_DEVICE:-}" ] || return 1
  printf '%s\n' "$CLUSTER_RDMA_DEVICE"
}

# #1442: devicePdBudget (CLUSTER_PD_DEVICE_BUDGET) is a measured constant frozen
# into Nix at eval time — nothing previously checked it against the machine it
# actually runs on. The reserve invariant (2 * maxKickstarts <= devicePdBudget)
# is arithmetic over that number, so a wrong one makes the guard's cap either
# unsafe (device has fewer domains than configured) or needlessly conservative
# (device has more). ibv_devinfo cannot run in the Nix sandbox — this is a
# runtime assertion, not an eval-time one.
#
# Sets PD_BUDGET_DETAIL for the caller's log line. Fail-closed: an unreadable
# probe is treated as unverified, not as passing.
pd_device_budget_ok() {
  local configured="${CLUSTER_PD_DEVICE_BUDGET:-0}"
  local device reported
  case "$configured" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [ "$configured" -gt 0 ] || return 0
  if ! device="$(active_rdma_device)"; then
    PD_BUDGET_DETAIL="no carrier-active RDMA device found to verify max_pd against"
    return 1
  fi
  reported="$("${CLUSTER_IBV_DEVINFO_BIN:-/usr/bin/ibv_devinfo}" -d "$device" -v 2>/dev/null | /usr/bin/awk '$1 == "max_pd:" { print $2; exit }')"
  case "$reported" in
    '' | *[!0-9]*)
      PD_BUDGET_DETAIL="ibv_devinfo -d $device -v did not report a readable max_pd; budget unverified"
      return 1
      ;;
  esac
  if [ "$reported" -lt "$configured" ]; then
    PD_BUDGET_DETAIL="$device reports max_pd=$reported, below the configured devicePdBudget=$configured — the reserve invariant would be evaluated against a budget the device does not have"
    return 1
  fi
  if [ "$reported" -gt "$configured" ]; then
    echo "cluster-join: $device reports max_pd=$reported, above the configured devicePdBudget=$configured (conservative; not refusing)" >&2
  fi
  return 0
}
