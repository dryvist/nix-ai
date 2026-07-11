# Night-rank launcher — runtime RDMA device detection, then exec the rank.
#
# The nix-darwin night-link-prep daemon converges this host's link address
# onto whichever Thunderbolt port the cable is in. This wrapper finds that
# interface, derives the RDMA device from it, writes the MLX_IBV_DEVICES
# matrix, and execs the real rank command (its own argv). Moving the cable
# needs no config change on this side either.
#
# Consumed environment (set declaratively by the launchd agent):
#   NIGHT_OWN_IP   this host's link address

iface=""
for cand in $(/sbin/ifconfig -l); do
  if /sbin/ifconfig "$cand" 2>/dev/null | grep -q "inet $NIGHT_OWN_IP "; then
    iface="$cand"
    break
  fi
done

if [ -z "$iface" ]; then
  echo "night-rank: link address $NIGHT_OWN_IP not on any interface; is the cable in?" >&2
  exit 1
fi

ibv_file="${TMPDIR:-/tmp}/mlx-night-ibv-devices.json"
printf '[[null,"rdma_%s"],["rdma_%s",null]]' "$iface" "$iface" > "$ibv_file"
export MLX_IBV_DEVICES="$ibv_file"
echo "night-rank: iface=$iface rdma_device=rdma_$iface"

exec "$@"
