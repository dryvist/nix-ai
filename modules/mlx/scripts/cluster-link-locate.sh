# shellcheck shell=bash
# Where is this host's Thunderbolt link address, and which RDMA device is it
# using? — the two questions cluster-join and the link watcher both ask before
# a rank start.
#
# Function definitions ONLY (no top-level statements), so cluster-join,
# cluster-detach and the link watcher can each concatenate it ahead of their own
# body and have every CLUSTER_* read resolve at call time.
#
# Split this finely on purpose: writeShellApplication runs shellcheck at default
# severity, so a function shipped to a consumer that never calls it fails the
# build with SC2329. Each consumer therefore gets exactly the layer it uses —
# detach only locates the port, join and the watcher also repair it
# (cluster-link-repair.sh).
#
# Consumed environment:
#   CLUSTER_STATIC_SELF_IP    this host's static link address
#   CLUSTER_RDMA_DEVICE       configured fallback RDMA device (clusterMode.rdmaDevice)
#   CLUSTER_PD_DEVICE_BUDGET  measured max_pd this host's config assumes (see #1442)

# Which interface, if any, currently holds this host's link address.
iface_holding_self_ip() {
  /sbin/ifconfig 2>/dev/null | /usr/bin/awk -v ip="$CLUSTER_STATIC_SELF_IP" '
    /^[a-z]/ { dev = $1; sub(/:$/, "", dev) }
    $1 == "inet" && $2 == ip { print dev; exit }
  '
}

# The carrier-active Thunderbolt port's RDMA device (e.g. "rdma_en2"), same
# discovery cluster-rank-launch.sh uses for the ibv matrix — never a pinned
# name, because moving the cable moves the port. Falls back to
# CLUSTER_RDMA_DEVICE when no carrier-active port has a matching rdma_<dev>.
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
  printf 'rdma_%s\n' "$CLUSTER_RDMA_DEVICE"
}

# #1442: devicePdBudget (CLUSTER_PD_DEVICE_BUDGET) is a measured constant frozen
# into Nix at eval time — nothing previously checked it against the machine it
# actually runs on. The reserve invariant (2 * maxKickstarts <= devicePdBudget)
# is arithmetic over that number, so a wrong one makes the guard's cap either
# unsafe (device has fewer domains than configured) or needlessly conservative
# (device has more). ibv_devinfo cannot run in the Nix sandbox — this is a
# runtime assertion, not an eval-time one.
#
# Sets PD_BUDGET_DETAIL for the caller's log line. Fail-closed, matching every
# other rung in this file: an unreadable probe is treated as unverified, not as
# passing, because "silently inert while reporting success" is the exact defect
# class this guard exists to catch (see file header).
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
  reported="$(/usr/bin/ibv_devinfo -d "$device" -v 2>/dev/null | /usr/bin/awk '$1 == "max_pd:" { print $2; exit }')"
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
    echo "cluster-link: $device reports max_pd=$reported, above the configured devicePdBudget=$configured (conservative; not refusing)" >&2
  fi
  return 0
}
