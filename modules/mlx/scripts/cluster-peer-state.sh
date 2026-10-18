# shellcheck shell=bash
# Fetch peer state and require the current session and a complete version match.

export PEER_GATE_REASON PEER_ARMED_AT PEER_PHASE PEER_START_AT PEER_FORMED_AT PEER_TS

peer_state_fetch() {
  PEER_STATE_RAW=""
  local body
  body="$("${CLUSTER_CURL_BIN:-/usr/bin/curl}" -fsS -m "${CLUSTER_PEER_STATE_TIMEOUT_SECS:-2}" \
    "http://${CLUSTER_STATIC_PEER_IP}:${CLUSTER_PEER_STATE_PORT}/" 2> /dev/null)" || return 1
  [ -n "$body" ] || return 1
  printf '%s' "$body" | jq -e 'type == "object"' > /dev/null 2>&1 || return 1
  PEER_STATE_RAW="$body"
}

peer_state_session_read() {
  local session
  PEER_GATE_REASON=""
  PEER_PHASE=""
  PEER_START_AT=""
  PEER_FORMED_AT=""
  PEER_TS=""
  [ -n "${JOIN_SESSION_ID:-}" ] || {
    PEER_GATE_REASON="no-session"
    return 1
  }
  if ! peer_state_fetch; then
    PEER_GATE_REASON="peer-state-unreachable"
    return 1
  fi
  session="$(jq -r '.session // ""' <<< "$PEER_STATE_RAW")"
  if [ "$session" != "$JOIN_SESSION_ID" ]; then
    PEER_GATE_REASON="peer-session-mismatch expected=$JOIN_SESSION_ID peer=${session:-empty}"
    return 1
  fi
  if ! peer_state_versions_match; then
    return 1
  fi
  PEER_PHASE="$(jq -r '.phase // ""' <<< "$PEER_STATE_RAW")"
  PEER_START_AT="$(jq -r '.start_at // 0' <<< "$PEER_STATE_RAW")"
  PEER_FORMED_AT="$(jq -r '.formed_at // 0' <<< "$PEER_STATE_RAW")"
  PEER_TS="$(jq -r '.ts // 0' <<< "$PEER_STATE_RAW")"
  case "$PEER_START_AT" in '' | *[!0-9]*) PEER_START_AT=0 ;; esac
  case "$PEER_FORMED_AT" in '' | *[!0-9]*) PEER_FORMED_AT=0 ;; esac
  case "$PEER_TS" in '' | *[!0-9]*) PEER_TS=0 ;; esac
}

peer_state_versions_match() {
  local key local_value peer_value local_software local_revision peer_revision
  local keys=(nix_ai mlx mlx_lm macos model model_revision)
  if ! peer_state_versions_validate; then
    return 1
  fi
  local_software="$PEER_SOFTWARE_JSON"
  local_revision="$PEER_CONFIGURATION_REVISION"
  for key in "${keys[@]}"; do
    local_value="$(jq -r --arg key "$key" '.[$key] // ""' <<< "$local_software")"
    peer_value="$(jq -r --arg key "$key" '.software[$key] // ""' <<< "$PEER_STATE_RAW")"
    if ! peer_version_value_known "$peer_value"; then
      PEER_GATE_REASON="version-unknown key=$key"
      return 1
    fi
    if [ "$local_value" != "$peer_value" ]; then
      PEER_GATE_REASON="version-mismatch key=$key local=$local_value peer=$peer_value"
      return 1
    fi
  done
  peer_revision="$(jq -r '.configuration_revision // ""' <<< "$PEER_STATE_RAW")"
  if ! peer_version_value_known "$peer_revision"; then
    PEER_GATE_REASON="version-unknown key=configuration_revision"
    return 1
  fi
  if [ "$local_revision" != "$peer_revision" ]; then
    PEER_GATE_REASON="version-mismatch key=configuration_revision local=$local_revision peer=$peer_revision"
    return 1
  fi
}

peer_armed_read() {
  local armed armed_at now age
  PEER_ARMED_AT=""
  if ! peer_state_session_read; then
    return 1
  fi
  if [ "$PEER_PHASE" != ready ]; then
    PEER_GATE_REASON="peer-not-ready phase=${PEER_PHASE:-unknown}"
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
  if [ "$age" -lt -5 ]; then
    PEER_GATE_REASON="peer-arm-future age=$age"
    return 1
  fi
  if [ "$age" -gt "${CLUSTER_JOIN_TIMEOUT_SECS:-600}" ]; then
    PEER_GATE_REASON="peer-arm-stale age=$age timeout=${CLUSTER_JOIN_TIMEOUT_SECS:-600}"
    return 1
  fi
  PEER_ARMED_AT="$armed_at"
}
