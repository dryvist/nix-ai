# shellcheck shell=bash
# Cluster peer state responder and reboot reset.

peer_state_reset_if_needed() {
  local boot mtime reset_reason="" macos software tmp versions
  : "${CLUSTER_PEER_STATE_FILE:?peer state file is required}"
  : "${CLUSTER_STATE_FILE:?link state file is required}"
  boot="$(current_boot_epoch)"
  case "$boot" in
    '' | *[!0-9]*)
      boot=0
      reset_reason="boot-time-unreadable"
      ;;
  esac
  mtime="$("${CLUSTER_STAT_BIN:-/usr/bin/stat}" -f %m "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || true)"
  if [ ! -f "$CLUSTER_STATE_FILE" ]; then
    reset_reason="link-state-missing"
  elif [ ! -f "$CLUSTER_PEER_STATE_FILE" ]; then
    reset_reason="peer-state-missing"
  else
    case "$mtime" in
      '' | *[!0-9]*) reset_reason="peer-state-mtime-unreadable" ;;
      *)
        if [ "$mtime" -lt "$boot" ]; then
          reset_reason="peer-state-from-previous-boot"
        fi
        ;;
    esac
  fi
  [ -n "$reset_reason" ] || return 0
  macos="$("${CLUSTER_SW_VERS_BIN:-/usr/bin/sw_vers}" -buildVersion 2> /dev/null || true)"
  versions="${CLUSTER_SOFTWARE_JSON:-}"
  [ -n "$versions" ] || versions="{}"
  software="$(jq -cn --arg macos "$macos" --argjson versions "$versions" \
    '{nix_ai: ($versions.nix_ai // ""), mlx: ($versions.mlx // ""), mlx_lm: ($versions.mlx_lm // ""), macos: $macos, model: ($versions.model // ""), model_revision: ($versions.model_revision // "" )}')"
  mkdir -p "$(dirname "$CLUSTER_PEER_STATE_FILE")"
  printf 'down\n' > "$CLUSTER_STATE_FILE"
  tmp="${CLUSTER_PEER_STATE_FILE}.tmp.$$"
  jq -nc --argjson boot "$boot" --argjson software "$software" \
    '{armed: false, armed_at: 0, boot: $boot, configuration_revision: "", session: "", phase: "abort", start_at: 0, formed_at: 0, software: $software, ts: 0}' > "$tmp"
  mv -f "$tmp" "$CLUSTER_PEER_STATE_FILE"
  echo "cluster-peer-state: reset state reason=$reset_reason"
}

cluster_peer_state_serve_main() {
  : "${CLUSTER_PEER_STATE_FILE:?peer state file is required}"
  : "${CLUSTER_PEER_STATE_PORT:?peer state port is required}"
  : "${CLUSTER_STATIC_SELF_IP:?static self ip is required}"
  local nc_bin="${CLUSTER_NC_BIN:-/usr/bin/nc}" retry_secs="${CLUSTER_PEER_STATE_RETRY_SECS:-5}"
  peer_state_reset_if_needed
  local unpublished='{"armed":false,"armed_at":0,"boot":0,"configuration_revision":"","session":"","phase":"abort","start_at":0,"formed_at":0,"software":{"nix_ai":"","mlx":"","mlx_lm":"","macos":"","model":"","model_revision":""},"ts":0}'
  echo "cluster-peer-state: serving $CLUSTER_PEER_STATE_FILE on $CLUSTER_STATIC_SELF_IP:$CLUSTER_PEER_STATE_PORT"

  while :; do
    local body="$unpublished"
    if [ -f "$CLUSTER_PEER_STATE_FILE" ]; then
      body="$(cat "$CLUSTER_PEER_STATE_FILE" 2> /dev/null || printf '%s' "$unpublished")"
    fi
    [ -n "$body" ] || body="$unpublished"
    # Content-Length and Connection: close let the client finish immediately;
    # -w bounds a peer that connects and then holds the only listener open.
    if printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
      "${#body}" "$body" |
      "$nc_bin" -l -w "${CLUSTER_PEER_STATE_TIMEOUT_SECS:-5}" \
        "$CLUSTER_STATIC_SELF_IP" "$CLUSTER_PEER_STATE_PORT" > /dev/null 2>&1; then
      sleep 0.2
    else
      sleep "$retry_secs"
    fi
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cluster_peer_state_serve_main
fi
