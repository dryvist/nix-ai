# shellcheck shell=bash
# Publish the state this host has proved locally for the current join.

generation_local_rev() {
  "${CLUSTER_DARWIN_VERSION_BIN:-/run/current-system/sw/bin/darwin-version}" --json 2> /dev/null |
    jq -r '.configurationRevision // empty' 2> /dev/null || true
}

peer_state_software_json() {
  local macos
  macos="$("${CLUSTER_SW_VERS_BIN:-/usr/bin/sw_vers}" -buildVersion 2> /dev/null)" || return 1
  [ -n "$macos" ] || return 1
  jq -ce --arg macos "$macos" '
    if type != "object" then empty else
      {nix_ai: .nix_ai, nix_darwin: .nix_darwin, mlx: .mlx, mlx_lm: .mlx_lm, macos: $macos}
      | select(all(.[]; type == "string"))
    end
  ' <<< "${CLUSTER_SOFTWARE_JSON:-}"
}

peer_state_write() {
  local armed="$1" armed_at="$2" out="${CLUSTER_PEER_STATE_FILE:-}" software boot generation ts tmp
  case "$armed" in true | false) ;; *) return 1 ;; esac
  case "$armed_at" in '' | *[!0-9]*) return 1 ;; esac
  [ -n "$out" ] || return 1
  software="$(peer_state_software_json)" || return 1
  boot="$(current_boot_epoch)"
  case "$boot" in '' | *[!0-9]*) boot=0 ;; esac
  generation="$(generation_local_rev)"
  ts="$(date +%s)"
  case "$ts" in '' | *[!0-9]*) return 1 ;; esac
  tmp="${out}.tmp.$$"
  mkdir -p "$(dirname "$out")" || return 1
  if ! jq -nc \
    --argjson armed "$armed" \
    --argjson armed_at "$armed_at" \
    --argjson boot "$boot" \
    --arg generation "$generation" \
    --argjson software "$software" \
    --argjson ts "$ts" \
    '{armed: $armed, armed_at: $armed_at, boot: $boot, generation: $generation, software: $software, ts: $ts}' \
    > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$out"
}

link_state_write() {
  local state="$1" out="${CLUSTER_STATE_FILE:-}" tmp
  case "$state" in up | down) ;; *) return 1 ;; esac
  [ -n "$out" ] || return 1
  tmp="${out}.tmp.$$"
  mkdir -p "$(dirname "$out")" || return 1
  printf '%s\n' "$state" > "$tmp" && mv -f "$tmp" "$out"
}
