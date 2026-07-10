#!/usr/bin/env bash
# Restart llama-swap proxy, then re-run the warmup agent so residents are
# faulted back in (mlx-warmup.py waits for the proxy before warming).
# Usage: mlx-default

launchctl kickstart -k "gui/$(id -u)/${MLX_LAUNCHD_LABEL:?}"
launchctl kickstart -k "gui/$(id -u)/${MLX_WARMUP_LABEL:?}"
echo "Default model restored."
