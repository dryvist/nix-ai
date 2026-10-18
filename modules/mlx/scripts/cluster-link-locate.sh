# shellcheck shell=bash
# Locate this host's Thunderbolt link address for cluster-join's J2 check.
#
# Function definitions ONLY (no top-level statements), so the join command can
# concatenate this ahead of its body and resolve CLUSTER_* values at call time.
#
# Split this finely on purpose: writeShellApplication runs shellcheck at default
# severity, so a function shipped to a consumer that never calls it fails the
# build with SC2329. The layer is therefore only included in cluster-join.
#
# Consumed environment:
#   CLUSTER_STATIC_SELF_IP  this host's static link address

# Which interface, if any, currently holds this host's link address.
iface_holding_self_ip() {
  /sbin/ifconfig 2>/dev/null | /usr/bin/awk -v ip="$CLUSTER_STATIC_SELF_IP" '
    /^[a-z]/ { dev = $1; sub(/:$/, "", dev) }
    $1 == "inet" && $2 == ip { print dev; exit }
  '
}
