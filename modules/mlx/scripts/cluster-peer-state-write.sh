# shellcheck shell=bash
# Publish the state this host has proved locally for the current join.

export PEER_GATE_REASON PEER_SOFTWARE_JSON PEER_CONFIGURATION_REVISION

configuration_revision_local() {
  "${CLUSTER_DARWIN_VERSION_BIN:-/run/current-system/sw/bin/darwin-version}" --json 2> /dev/null |
    jq -r '.configurationRevision // empty' 2> /dev/null || true
}

peer_state_software_json() {
  local macos model model_revision
  macos="$("${CLUSTER_SW_VERS_BIN:-/usr/bin/sw_vers}" -buildVersion 2> /dev/null || true)"
  model="$(jq -r '.model // ""' <<< "${CLUSTER_SOFTWARE_JSON:-}")"
  model_revision="$(jq -r '.model_revision // ""' <<< "${CLUSTER_SOFTWARE_JSON:-}")"
  model="${JOIN_MODEL_ID:-$model}"
  model_revision="${JOIN_MODEL_REVISION:-$model_revision}"
  jq -c --arg macos "$macos" --arg model "$model" --arg model_revision "$model_revision" '
    if type != "object" then empty else
      {
        nix_ai: (if (.nix_ai | type) == "string" then .nix_ai else "" end),
        mlx: (if (.mlx | type) == "string" then .mlx else "" end),
        mlx_lm: (if (.mlx_lm | type) == "string" then .mlx_lm else "" end),
        macos: $macos,
        model: $model,
        model_revision: $model_revision
      }
    end
  ' <<< "${CLUSTER_SOFTWARE_JSON:-}"
}

peer_version_value_known() {
  case "$1" in
    '' | [Nn][Uu][Ll][Ll] | [Uu][Nn][Kk][Nn][Oo][Ww][Nn] | *[Dd][Ii][Rr][Tt][Yy]*) return 1 ;;
    *) return 0 ;;
  esac
}

peer_state_versions_validate() {
  local software configuration_revision key value
  local keys=(nix_ai mlx mlx_lm macos model model_revision)
  software="$(peer_state_software_json)" || {
    PEER_GATE_REASON="version-unknown key=software"
    return 1
  }
  for key in "${keys[@]}"; do
    value="$(jq -r --arg key "$key" '.[$key] // ""' <<< "$software")"
    if ! peer_version_value_known "$value"; then
      PEER_GATE_REASON="version-unknown key=$key"
      return 1
    fi
  done
  configuration_revision="$(configuration_revision_local)"
  if ! peer_version_value_known "$configuration_revision"; then
    PEER_GATE_REASON="version-unknown key=configuration_revision"
    return 1
  fi
  PEER_SOFTWARE_JSON="$software"
  PEER_CONFIGURATION_REVISION="$configuration_revision"
}

peer_state_write() {
  local armed="$1" armed_at="$2" session="${3:-}" phase="${4:-}" start_at="${5:-0}"
  local out="${CLUSTER_PEER_STATE_FILE:-}" software boot configuration_revision ts tmp
  case "$armed" in true | false) ;; *) return 1 ;; esac
  case "$armed_at" in '' | *[!0-9]*) return 1 ;; esac
  case "$phase" in preparing | ready | commit | abort | formed) ;; *) return 1 ;; esac
  case "$start_at" in '' | *[!0-9]*) return 1 ;; esac
  case "$phase" in
    preparing | ready | commit | formed)
      [[ "$session" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || return 1
      ;;
  esac
  case "$phase:$armed" in
    preparing:false | ready:true | commit:true | abort:false | formed:true) ;;
    *) return 1 ;;
  esac
  [ -n "$out" ] || return 1
  if [ "$phase" = ready ] && ! peer_state_versions_validate; then
    return 1
  fi
  software="$(peer_state_software_json)" || return 1
  configuration_revision="$(configuration_revision_local)"
  boot="$(current_boot_epoch)"
  case "$boot" in '' | *[!0-9]*) boot=0 ;; esac
  ts="$(date +%s)"
  case "$ts" in '' | *[!0-9]*) return 1 ;; esac
  tmp="${out}.tmp.$$"
  mkdir -p "$(dirname "$out")" || return 1
  if ! jq -nc \
    --argjson armed "$armed" \
    --argjson armed_at "$armed_at" \
    --argjson boot "$boot" \
    --arg configuration_revision "$configuration_revision" \
    --arg session "$session" \
    --arg phase "$phase" \
    --argjson start_at "$start_at" \
    --argjson software "$software" \
    --argjson ts "$ts" \
    '{armed: $armed, armed_at: $armed_at, boot: $boot, configuration_revision: $configuration_revision,
      session: $session, phase: $phase, start_at: $start_at, software: $software, ts: $ts}' \
    > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv -f "$tmp" "$out"; then
    rm -f "$tmp"
    return 1
  fi
}

link_state_write() {
  local state="$1" out="${CLUSTER_STATE_FILE:-}" tmp
  case "$state" in up | down) ;; *) return 1 ;; esac
  [ -n "$out" ] || return 1
  tmp="${out}.tmp.$$"
  mkdir -p "$(dirname "$out")" || return 1
  printf '%s\n' "$state" > "$tmp" && mv -f "$tmp" "$out"
}
