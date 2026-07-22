#!/usr/bin/env bash
# Show MLX inference server state.
# Usage: mlx-status

port="${MLX_PORT:?}"
api="${MLX_API_URL:?}"

# The process on $port is the llama-swap supervisor. Find the selected MLX model
# server backend for memory reporting.
if lsof -ti :"$port" 2>/dev/null | head -1 > /dev/null; then
  api_root="${api%/v1*}"
  _running=$(curl -sf "${api_root}/running" 2>/dev/null)
  model=$(echo "${_running}" | jq -r '.running[0].model // "(none loaded)"' 2>/dev/null || echo "(none loaded)")

  # Get memory from the model-server child process (the real memory consumer).
  # Prefer the backend that is a child of the proxy bound to $port.
  proxy_pid=$(lsof -ti :"$port" 2>/dev/null | head -1)
  model_server_pid=""
  if [ -n "$proxy_pid" ]; then
    model_server_pid=$(pgrep -P "$proxy_pid" -f "${MLX_MODEL_SERVER_PROCESS_PATTERN:?}" 2>/dev/null | head -1)
  fi
  # Fallback: broad search if no child match (unexpected layout).
  if [ -z "$model_server_pid" ]; then
    model_server_pid=$(pgrep -f "${MLX_MODEL_SERVER_PROCESS_PATTERN:?}" 2>/dev/null | head -1)
  fi

  if [ -n "$model_server_pid" ]; then
    mem_mb=$(/usr/bin/footprint -p "$model_server_pid" 2>/dev/null \
      | awk '/Footprint:/ { for(i=1;i<=NF;i++) if($i=="Footprint:") {
          val=$(i+1); unit=$(i+2)
          if(unit~/GB/) printf "%.0f\n", val*1024
          else if(unit~/MB/) print val
          else if(unit~/KB/) printf "%.0f\n", val/1024
          exit }}')
    if [ -z "$mem_mb" ] || [ "$mem_mb" = "0" ]; then
      mem_kb=$(ps -o rss= -p "$model_server_pid" 2>/dev/null)
      mem_mb=$(( ${mem_kb:-0} / 1024 ))
    fi
    uptime=$(ps -o etime= -p "$model_server_pid")
  else
    mem_mb=0
    uptime="n/a"
    model_server_pid="none"
  fi

  printf "running  proxy_pid=%s  model_server_pid=%s  model=%s  mem=%.1fGB  uptime=%s\n" \
    "$proxy_pid" "$model_server_pid" "$model" "$(echo "scale=1; $mem_mb/1024" | bc)" "$uptime"
else
  echo "stopped"
fi
