# shellcheck shell=bash
# Shared cache check and cluster guard for static resident MLX model-server LaunchAgents.

server="$1"
shift

model_id=
if [ "$#" -ge 2 ] && [ "$1" = "--model" ]; then
  model_id="$2"
fi

# Cluster guard, on the same state the darwin-rebuild clustered check reads.
# Clustered = link-state up and peer armed. A missing state file means not
# clustered. A state file that exists but cannot be read or parsed refuses,
# because the wired-memory failsafe cannot tell what the peer holds. Every
# decision is logged to stderr, which launchd writes to the agent's error log.
cluster_dir="$HOME/Library/Application Support/mlx-cluster"
link_file="$cluster_dir/link-state"
peer_file="$cluster_dir/peer-state.json"
refuse() {
  printf 'mlx-model-server-preflight: refuse reason=%s model=%s link-state=%s armed=%s\n' \
    "$1" "${model_id:-none}" "${link_state:-missing}" "${peer_armed:-missing}" >&2
  exit 75
}
link_state=missing
if [ -e "$link_file" ]; then
  link_state=$(cat "$link_file" 2>/dev/null) || refuse link-state-unreadable
fi
peer_armed=missing
if [ -e "$peer_file" ]; then
# The file must hold exactly one JSON object whose armed value, when present, is a
# boolean. Empty, multi-document, non-object and non-boolean files all refuse.
peer_armed=$(jq -rs 'if length == 1 and (.[0] | type) == "object" then (.[0].armed // false | if type == "boolean" then tostring else error("armed is not a boolean") end) else error("peer-state is not one JSON object") end' "$peer_file" 2>/dev/null) || refuse peer-state-unreadable
fi
if [ "$link_state" = up ] && [ "$peer_armed" = true ]; then
  refuse clustered
fi
printf 'mlx-model-server-preflight: allow model=%s link-state=%s armed=%s cluster=not-clustered\n' \
  "${model_id:-none}" "$link_state" "$peer_armed" >&2

if [ -n "$model_id" ] && [ ! -d "$model_id" ]; then
  cache_root="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
  snapshot_dir="$cache_root/models--${model_id//\//--}/snapshots"
  cached_snapshot=
  for snapshot in "$snapshot_dir"/*; do
    if [ -d "$snapshot" ]; then
      cached_snapshot="$snapshot"
      break
    fi
  done
  if [ -z "$cached_snapshot" ]; then
    printf 'mlx-model-server-preflight: model %s is missing from HF cache; expected a snapshot at %s/*\n' \
      "$model_id" "$snapshot_dir" >&2
    exit 1
  fi
fi

exec "$server" "$@"
