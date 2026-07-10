#!/usr/bin/env bash
# Restart the llama-swap proxy gracefully, then re-run the warmup agent so
# residents are faulted back in (mlx-warmup.py waits for the proxy before
# warming).
#
# The proxy MUST stop with SIGTERM, never SIGKILL. llama-swap only runs its
# graceful upstream shutdown on SIGTERM; `launchctl kickstart -k` SIGKILLs it,
# so a vllm-mlx worker that is mid-load or mid-request survives as an orphan
# (reparented to PID 1, still bound to its port). The relaunched proxy then
# dies on bind ("upstream exited unexpectedly") and untracks the model, while
# the orphan keeps answering proxied requests — a resident that never truly
# reloads (#1182). So SIGTERM the proxy and wait for it (and its children) to
# exit before the fresh instance claims the worker ports; launchd's KeepAlive
# brings the proxy back cleanly. Only the warmup agent, which owns no
# port-holding children, is safe to `kickstart -k`.
# Usage: mlx-default

uid=$(id -u)
label="${MLX_LAUNCHD_LABEL:?}"

# PID of the running proxy, if any (empty when already stopped).
pid=$(launchctl print "gui/$uid/$label" 2>/dev/null |
  awk -F' = ' '/^\tpid = /{print $2; exit}' || true)

# SIGTERM the proxy so llama-swap gracefully stops its vllm-mlx workers before
# exiting; KeepAlive then relaunches it.
launchctl stop "$label"

# Wait for the old proxy process (and, via graceful shutdown, its children) to
# fully exit before the fresh instance starts binding worker ports.
if [ -n "$pid" ]; then
  for ((i = 0; i < 60; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
fi

launchctl kickstart -k "gui/$uid/${MLX_WARMUP_LABEL:?}"
echo "Default model restored."
