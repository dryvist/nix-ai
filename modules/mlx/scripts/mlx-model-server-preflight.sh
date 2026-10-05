# shellcheck shell=bash
# Shared cache check for static resident MLX model-server LaunchAgents.

server="$1"
shift

model_id=
if [ "$#" -ge 2 ] && [ "$1" = "--model" ]; then
  model_id="$2"
fi

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
