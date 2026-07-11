# Shared night-link discovery helpers — concatenated ahead of the watcher and
# the rank launcher by writeShellApplication (this file is not standalone).
#
# The Thunderbolt RDMA link carries no configured IP: the cabled port is
# auto-detected and the interface's automatic IPv6 link-local (fe80::) is the
# link identity, so moving the cable to another port needs no config edit.

# First Thunderbolt port with an active link; honors NIGHT_IFACE_OVERRIDE.
night_detect_iface() {
  if [ -n "${NIGHT_IFACE_OVERRIDE:-}" ]; then
    printf '%s\n' "$NIGHT_IFACE_OVERRIDE"
    return 0
  fi
  local dev
  # "Thunderbolt [0-9]" only: the virtual "Thunderbolt Bridge" port (device
  # bridge0) also starts with "Thunderbolt" and must never be a candidate.
  for dev in $(/usr/sbin/networksetup -listallhardwareports \
                | /usr/bin/awk '/^Hardware Port: Thunderbolt [0-9]/{getline; print $2}'); do
    if /sbin/ifconfig "$dev" 2>/dev/null | /usr/bin/grep -q "status: active"; then
      printf '%s\n' "$dev"
      return 0
    fi
  done
  return 1
}

# This host's link-local address on $1, WITH the %scope suffix macOS prints.
night_own_ll() {
  /sbin/ifconfig "$1" inet6 2>/dev/null \
    | /usr/bin/awk '$1=="inet6" && $2 ~ /^fe80/{print $2; exit}'
}

# Peer's link-local on $1: solicit with all-nodes multicast (ff02::1), then
# read the neighbor cache, excluding our own address. Empty output = no peer.
night_peer_ll() {
  local iface="$1" own
  own="$(night_own_ll "$iface")"
  /sbin/ping6 -c 2 "ff02::1%$iface" > /dev/null 2>&1 || true
  # Match the Netif column exactly — a substring test on %en2 would also
  # match neighbors on en20/en21.
  /usr/sbin/ndp -an 2>/dev/null \
    | /usr/bin/awk -v iface="$iface" -v own="$own" \
        '$1 ~ /^fe80/ && $3 == iface && $1 != own { print $1; exit }'
}
