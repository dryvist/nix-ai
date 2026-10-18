# shellcheck shell=bash
# Fetch the peer state and require a fresh, armed, matching software generation.

export PEER_GATE_REASON PEER_ARMED_AT

peer_state_fetch() {
  PEER_STATE_RAW=""
  local body
  body="$("${CLUSTER_CURL_BIN:-/usr/bin/curl}" -fsS -m "${CLUSTER_PEER_STATE_TIMEOUT_SECS:-2}" \
    "http://${CLUSTER_STATIC_PEER_IP}:${CLUSTER_PEER_STATE_PORT}/" 2> /dev/null)" || return 1
  [ -n "$body" ] || return 1
  printf '%s' "$body" | jq -e 'type == "object"' > /dev/null 2>&1 || return 1
  PEER_STATE_RAW="$body"
}

peer_armed_read() {
  local armed armed_at now age peer_value local_value key local_software peer_generation local_generation
  local keys=(nix_ai nix_darwin mlx mlx_lm macos)
  PEER_GATE_REASON=""
  PEER_ARMED_AT=""
  if ! peer_state_fetch; then
    PEER_GATE_REASON="peer-state-unreachable"
    return 1
  fi
  local_software="$(peer_state_software_json)" || {
    PEER_GATE_REASON="local-software-unavailable"
    return 1
  }
  for key in "${keys[@]}"; do
    local_value="$(jq -r --arg key "$key" '.[$key] // ""' <<< "$local_software")"
    peer_value="$(jq -r --arg key "$key" '.software[$key] // ""' <<< "$PEER_STATE_RAW")"
    if [ "$local_value" != "$peer_value" ]; then
      PEER_GATE_REASON="generation-mismatch key=$key local=$local_value peer=$peer_value"
      return 1
    fi
  done
  local_generation="$(generation_local_rev)"
  peer_generation="$(jq -r '.generation // ""' <<< "$PEER_STATE_RAW")"
  if [ "$local_generation" != "$peer_generation" ]; then
    PEER_GATE_REASON="generation-mismatch key=generation local=$local_generation peer=$peer_generation"
    return 1
  fi
  armed="$(jq -r '.armed // false' <<< "$PEER_STATE_RAW")"
  armed_at="$(jq -r '.armed_at // 0' <<< "$PEER_STATE_RAW")"
  case "$armed_at" in '' | *[!0-9]*) armed_at=0 ;; esac
  if [ "$armed" != true ] || [ "$armed_at" -le 0 ]; then
    PEER_GATE_REASON="peer-not-armed"
    return 1
  fi
  now="$(date +%s)"
  case "$now" in '' | *[!0-9]*)
    PEER_GATE_REASON="clock-unavailable"
    return 1
    ;;
  esac
  age=$((now - armed_at))
  if [ "$age" -gt "${CLUSTER_JOIN_TIMEOUT_SECS:-600}" ]; then
    PEER_GATE_REASON="peer-arm-stale age=$age timeout=${CLUSTER_JOIN_TIMEOUT_SECS:-600}"
    return 1
  fi
  PEER_ARMED_AT="$armed_at"
}
