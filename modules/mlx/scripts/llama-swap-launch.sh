#!/usr/bin/env bash
# llama-swap-launch — reap anything holding our ports, then exec the proxy.
#
# The reap logic lives in llama-swap-reap.sh, concatenated ahead of this file
# by modules/mlx/llama-swap-launch-pkg.nix, so tests/test-worker-port-reap.sh
# can source it directly without triggering the exec below. Read that file's
# header for the full story: launchd stops the proxy but leaves `uv run`/`uvx`
# grandchildren running (re-parented to launchd, ppid 1) still holding their
# port, and the predicate that finds them is port ownership, not process
# ancestry or a cmdline pattern — the prior pattern-based reap here was proven
# a silent no-op for the standalone worker (2026-07-26).
#
# Consumed environment: see llama-swap-reap.sh's header (MLX_PORT,
# MLX_WORKER_PORT_RANGE_START, MLX_WORKER_PORT_COUNT, MLX_LSOF_BIN,
# MLX_KILL_BIN — all baked by modules/mlx/launchd.nix).
set -euo pipefail

if ! mlx_reap_orphan_ports; then
  # Never exec into a guaranteed bind failure: exiting non-zero makes launchd
  # retry after ThrottleInterval, which is a real recovery path. Starting
  # anyway would resume the exact failure this script exists to prevent — a
  # worker that dies instantly on [Errno 48] address already in use, leaving
  # llama-swap to answer every completion with an HTTP 200 and a ZERO-BYTE
  # body until its own health-check timeout.
  echo "$(date -u +%FT%TZ) llama-swap-launch: port(s) still held; refusing to start" >&2
  exit 1
fi

exec llama-swap "$@"
