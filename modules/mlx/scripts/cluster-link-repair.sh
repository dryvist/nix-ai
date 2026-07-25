# shellcheck shell=bash
# Thunderbolt link-prep verification and repair — shared by cluster-join and the
# link watcher (cluster-detach only needs cluster-link-locate.sh, which this
# file assumes is concatenated alongside it).
#
# Function definitions ONLY (no top-level statements). This was a copy inside
# cluster-join.sh until 2026-07-25, when the watcher needed the same logic to
# stop starting ranks that cannot bind — and a third copy of a repair procedure
# is how two of them quietly diverge.
#
# Consumed environment:
#   CLUSTER_STATIC_SELF_IP  this host's static link address
#
# Grants used (nix-darwin sudoers, cluster-ops): `ifconfig bridge0 deletem *`
# and `ifconfig en[0-9]* up`. The alias form rides the same space-spanning
# `en[0-9]* up` grant (verified 2026-07-19 rc=0).

# Physical Thunderbolt devices (the cable lands on exactly one; the others are
# uncabled). Same discovery cluster-link-prep uses -- never the service order,
# which lists nothing when no per-port services exist.
tb_devices() {
  /usr/sbin/networksetup -listallhardwareports \
    | /usr/bin/awk '/^Hardware Port: Thunderbolt [0-9]/{getline; sub(/^Device: /, ""); print}'
}

# Prep is healthy when this host's own link address is aliased on a physical
# port that is NOT enslaved in the Thunderbolt bridge (bridge0) and that has
# carrier.
link_prep_ok() {
  local dev
  dev="$(iface_holding_self_ip)"
  [ -n "$dev" ] || return 1
  [ "$dev" = "bridge0" ] && return 1
  # port must not be a bridge0 member (re-enslavement is the classic prep loss)
  if /sbin/ifconfig bridge0 2>/dev/null | /usr/bin/grep -qw "member: $dev"; then
    return 1
  fi
  # port must have carrier: cluster-detach admin-downs the link but leaves the
  # alias in place, so a down-but-aliased port looks configured yet cannot
  # rendezvous. Require it up so a rejoin repairs (brings it back up) instead
  # of blocking forever on an unreachable peer.
  case "$(/sbin/ifconfig "$dev" 2>/dev/null)" in
    *"status: active"*) ;;
    *) return 1 ;;
  esac
  return 0
}

# Direct, granted link repair for when activation cannot (it can hang on an
# unrelated activation step, or need a second pass to bring a just-freed port
# up). Frees every Thunderbolt port from bridge0 and admin-ups it (no address,
# so no stray route), then aliases this node's link IP on the ONE port that
# shows carrier -- matching link-prep's single-active-port rule so the /24 route
# cannot bind to an uncabled sibling. Hex netmask avoids a dotted quad in a
# public repo.
repair_link_direct() {
  local dev active=""
  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    if /sbin/ifconfig bridge0 2>/dev/null | /usr/bin/grep -qw "member: $dev"; then
      sudo -n /sbin/ifconfig bridge0 deletem "$dev" > /dev/null 2>&1 || true
    fi
    sudo -n /sbin/ifconfig "$dev" up > /dev/null 2>&1 || true
  done < <(tb_devices)
  # carrier can take a moment after admin-up; retry briefly.
  for _ in 1 2 3 4 5; do
    active="$(tb_devices | while IFS= read -r dev; do
      case "$(/sbin/ifconfig "$dev" 2>/dev/null)" in
        *"status: active"*) echo "$dev"; break ;;
      esac
    done)"
    [ -n "$active" ] && break
    sleep 2
  done
  [ -n "$active" ] || return 1
  sudo -n /sbin/ifconfig "$active" alias "$CLUSTER_STATIC_SELF_IP" 0xffffff00 up > /dev/null 2>&1 || true
}
