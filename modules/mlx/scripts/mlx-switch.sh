#!/usr/bin/env bash
# Switch the active MLX model via llama-swap proxy.
# Registry (Nix-declared) models only — anything else in the HF cache is
# served on demand by the dynamic tier (MLX_DYNAMIC_API_URL), no switch needed.
# Usage: mlx-switch <model-id>

model="${1:?Usage: mlx-switch <model>}"

mlx-preflight "$model" || exit 1

# The config is the immutable Nix-generated file; a model missing from it is
# not an error to repair at runtime — it is either served by the dynamic tier
# or needs a Nix registry entry (one reviewed attr).
config_path="${MLX_LLAMA_SWAP_CONFIG:-}"
if [ -n "$config_path" ] && [ -f "$config_path" ]; then
  if ! jq -e --arg m "$model" '.models[$m]' "$config_path" > /dev/null 2>&1; then
    echo "ERROR: $model is not in the llama-swap registry (Nix-declared)." >&2
    if [ -n "${MLX_DYNAMIC_API_URL:-}" ]; then
      echo "Cached models are served on demand by the dynamic tier instead:" >&2
      echo "  ${MLX_DYNAMIC_API_URL} (just name the model in the request)" >&2
    else
      echo "Add it to the Nix registry (services.aiStack / programs.mlx.models)." >&2
    fi
    exit 1
  fi
fi

echo "Switching to $model (this may take 20-60s for large models)..."

# Trigger the swap by sending a minimal request with the target model.
# llama-swap stops the current backend and starts the new one.
if ! curl -sf "${MLX_API_URL:?}/chat/completions" \
  -H "Content-Type: application/json" \
  --max-time 300 \
  -d "$(jq -n --arg m "$model" '{model: $m, messages: [{role: "user", content: "ping"}], max_tokens: 1}')" \
  > /dev/null 2>&1; then
  echo "Switch failed. Check: mlx-status" >&2
  exit 1
fi

echo "Model $model is now active."
