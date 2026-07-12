# Cluster-rank launcher — computes the JACCL distributed-init environment at
# RUNTIME (interface + addresses are physical facts discovered from the cable,
# never committed), then execs the mlx_lm.server rank passed as "$@".
#
# Consumed environment (set declaratively by the launchd agent):
#   CLUSTER_ROLE                   coordinator | worker
#   CLUSTER_LINK_DISCOVERY         link-local (default) | static
#   CLUSTER_RENDEZVOUS_PORT        JACCL rendezvous port
#   CLUSTER_STATIC_COORDINATOR_IP  static-mode coordinator address (fallback)
#   CLUSTER_IFACE_OVERRIDE         optional cabled-port override
#   CLUSTER_RDMA_DEVICE            optional ibv device override (default rdma_<iface>)

iface="$(cluster_detect_iface)" || {
  echo "cluster-rank: no cabled Thunderbolt port detected; refusing to start" >&2
  exit 1
}

case "${CLUSTER_LINK_DISCOVERY:-static}" in
  static)
    coord="$CLUSTER_STATIC_COORDINATOR_IP"
    ;;
  *)
    # GATE VALIDATED 2026-07-11 and REJECTED: the pinned mlx-lm's JACCL
    # rendezvous parser is IPv4-only (even [::1]:port fails with "Can't
    # parse address"), so this branch cannot work today. Kept for a future
    # mlx-lm that learns IPv6 — fe80 reachability itself verified fine.
    if [ "$CLUSTER_ROLE" = "coordinator" ]; then
      coord="$(cluster_own_ll "$iface")"
    else
      coord="$(cluster_peer_ll "$iface")"
    fi
    if [ -z "$coord" ]; then
      echo "cluster-rank: no link-local $CLUSTER_ROLE address resolvable on $iface" >&2
      exit 1
    fi
    coord="[$coord]" # bracket the v6 literal for the :port join
    ;;
esac

dev="${CLUSTER_RDMA_DEVICE:-rdma_$iface}"
# Deterministic path, not mktemp: exec replaces this shell, so nothing could
# clean a fresh temp file per launch; one stable per-user file self-overwrites.
matrix="${TMPDIR:-/tmp}/mlx-cluster-ibv-$(id -u).json"
printf '[[null, "%s"], ["%s", null]]\n' "$dev" "$dev" > "$matrix"

export MLX_JACCL_COORDINATOR="$coord:$CLUSTER_RENDEZVOUS_PORT"
export MLX_IBV_DEVICES="$matrix"
echo "cluster-rank: iface=$iface dev=$dev coordinator=$MLX_JACCL_COORDINATOR"
exec "$@"
