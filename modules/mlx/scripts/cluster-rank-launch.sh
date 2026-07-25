#!/usr/bin/env bash
#
# Cluster rank launcher — discovers the RDMA device at start, then execs the
# real rank command.
#
# Everything else in the rank's env contract is baked at eval. The RDMA device
# cannot be, because it names a PHYSICAL PORT: move the Thunderbolt cable and a
# pinned `rdma_en2` names a device with no link. The IP layer already survives a
# port move (nix-darwin's cluster-link prep addresses whichever port has
# carrier), so pinning only the RDMA layer is an asymmetry, and it fails badly —
# a peer that never appears is indistinguishable from a wedge, so the surviving
# rank blocks forever in jaccl::MeshImpl::recv while /v1/models still answers.
#
# Per the MLX docs, row i of the matrix lists the devices rank i uses to reach
# each other rank, and each rank consumes only its OWN row. So each host writes
# [[null, MY_DEV], [MY_DEV, null]] from its own locally-discovered device and
# the result is correct even when the two hosts land on different ports.
#
# Discovery never guesses from interface numbering — en1 is Thunderbolt on one
# Mac and Wi-Fi on another. It enumerates the Thunderbolt ports by name, keeps
# the one with carrier, and requires a matching rdma_<dev> in ibv_devices.
#
# System binaries are called by absolute path (the sanitized PATH carries only
# the nix runtimeInputs), matching the other cluster scripts.
set -euo pipefail

matrix_file="${CLUSTER_IBV_MATRIX_FILE:?CLUSTER_IBV_MATRIX_FILE is required}"
fallback_device="${CLUSTER_RDMA_DEVICE:?CLUSTER_RDMA_DEVICE is required}"

log() { printf '[cluster-rank-launch] %s\n' "$*" >&2; }

# First Thunderbolt port with carrier whose rdma_<dev> exists in ibv_devices.
discover_rdma_device() {
  local dev
  while read -r dev; do
    [ -n "$dev" ] || continue
    /sbin/ifconfig "$dev" 2>/dev/null | grep -q 'status: active' || continue
    if /usr/bin/ibv_devices 2>/dev/null | awk '{print $1}' | grep -qx "rdma_$dev"; then
      printf 'rdma_%s\n' "$dev"
      return 0
    fi
    log "thunderbolt $dev has carrier but no rdma_$dev in ibv_devices"
  done < <(
    /usr/sbin/networksetup -listallhardwareports 2>/dev/null |
      awk '/^Hardware Port: Thunderbolt [0-9]/ { tb = 1; next }
           /^Device:/ { if (tb) print $2; tb = 0 }'
  )
  return 1
}

if device="$(discover_rdma_device)"; then
  log "using discovered RDMA device $device"
else
  device="$fallback_device"
  log "WARNING: no carrier-active Thunderbolt port with a matching rdma_ device."
  log "WARNING: falling back to the configured rdmaDevice '$device'. If the cable"
  log "WARNING: moved ports, the mesh will not form and this rank will hang in"
  log "WARNING: distributed init. Check 'ibv_devices' and clusterMode.rdmaDevice."
fi

mkdir -p "$(dirname "$matrix_file")"
printf '[[null, "%s"], ["%s", null]]\n' "$device" "$device" >"$matrix_file"
export MLX_IBV_DEVICES="$matrix_file"

exec "$@"
