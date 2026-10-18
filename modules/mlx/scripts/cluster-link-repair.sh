# shellcheck shell=bash
# Read-only link-preparation check used by cluster-join.

link_prep_ok() {
  local dev
  dev="$(iface_holding_self_ip)"
  [ -n "$dev" ] || return 1
  [ "$dev" != bridge0 ] || return 1
  if /sbin/ifconfig bridge0 2> /dev/null | /usr/bin/grep -qw "member: $dev"; then
    return 1
  fi
  case "$(/sbin/ifconfig "$dev" 2> /dev/null)" in
    *"status: active"*) return 0 ;;
    *) return 1 ;;
  esac
}
