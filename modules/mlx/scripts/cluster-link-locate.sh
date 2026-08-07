# shellcheck shell=bash
# Where is this host's Thunderbolt link address? — the one question all three
# cluster scripts ask.
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
#   CLUSTER_STATIC_SELF_IP  this host's static link address

# Which interface, if any, currently holds this host's link address.
iface_holding_self_ip() {
  /sbin/ifconfig 2>/dev/null | /usr/bin/awk -v ip="$CLUSTER_STATIC_SELF_IP" '
    /^[a-z]/ { dev = $1; sub(/:$/, "", dev) }
    $1 == "inet" && $2 == ip { print dev; exit }
  '
}
