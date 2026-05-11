#!/usr/bin/env bash
# List all downloaded MLX models with memory fit and registration status.
# Usage: mlx-models

hf_home="${MLX_HF_HOME:-/Volumes/HuggingFace}"
port="${MLX_PORT:-11434}"
api="${MLX_API_URL:-http://127.0.0.1:$port/v1}"
config_path="${MLX_LLAMA_SWAP_CONFIG:-}"

total_bytes=$(sysctl -n hw.memsize)
total_gb=$(( total_bytes / 1073741824 ))
available_gb=$(( total_gb - 20 ))

# Get currently running model
running_model=$(curl -sf "${api%/v1}/running" 2>/dev/null | jq -r '.running[0].model // ""' 2>/dev/null || echo "")

# Load registered models from llama-swap config (if available)
registered_models=""
if [ -n "$config_path" ] && [ -f "$config_path" ]; then
  registered_models=$(jq -r '.models | keys[]' "$config_path" 2>/dev/null)
fi

printf "%-55s %8s %8s %-7s %s\n" "MODEL" "SIZE" "EST.MEM" "FIT" "REG"
printf "%-55s %8s %8s %-7s %s\n" "-----" "----" "-------" "---" "---"

for model_dir in "$hf_home/hub"/models--*; do
  [ -d "$model_dir" ] || continue

  # Convert cache path back to model ID
  dir_name=$(basename "$model_dir")
  model_id="${dir_name#models--}"
  model_id="${model_id//--//}"

  # Size in GB
  read -r size_gb est_gb < <(
    du -sk "$model_dir" | awk '{
      gb = int($1 / 1048576 + 0.5)
      est = int(gb * 1.3 + 0.5)
      print gb, est
    }'
  )

  # Memory fit status
  if [ "$size_gb" -gt "$available_gb" ]; then
    fit="NO-FIT"
  elif [ "$est_gb" -gt "$available_gb" ]; then
    fit="TIGHT"
  else
    fit="OK"
  fi

  # Registration status
  reg="--"
  if [ -n "$registered_models" ]; then
    if echo "$registered_models" | grep -qxF "$model_id"; then
      reg="YES"
    fi
  fi

  # Running indicator
  marker="  "
  if [ "$model_id" = "$running_model" ]; then
    marker="* "
  fi

  printf "%s%-53s %5d GB %5d GB %-7s %s\n" "$marker" "$model_id" "$size_gb" "$est_gb" "$fit" "$reg"
done

echo ""
echo "System: ${total_gb} GB total, 20 GB reserved, ${available_gb} GB available for models"
echo "* = currently running | REG = registered in llama-swap config"
echo "Run 'mlx-discover' to register unregistered models"
