#!/usr/bin/env bash
# Regression guard: modelServerProcessPattern.mlx-lm must match the REAL
# built mlx-lm-server launcher script.
#
# modules/mlx/default.nix derives this pattern from
# mlx-lm-server.nix's launchScriptBasename instead of a hand-typed literal,
# specifically so it cannot silently drift from the real invocation the way
# "/mlx_lm\.server" did after #1368 introduced mlx-lm-launch.py (see
# scripts/llama-swap-reap.sh's header for the measured incident). This test
# is what fails if a future change reintroduces a hand-typed literal here,
# defeating that derivation.
set -o errexit -o nounset -o pipefail

pattern="${MLX_MODEL_SERVER_PATTERN:?MLX_MODEL_SERVER_PATTERN unset}"
launcher="${MLX_LM_SERVER_EXE:?MLX_LM_SERVER_EXE unset}"

if ! grep -E -- "$pattern" "$launcher"; then
  echo "modelServerProcessPattern.mlx-lm ('$pattern') does not match the real mlx-lm-server launcher script ($launcher) -- the pgrep/pkill pattern has drifted from the actual invocation (see #1368 for the last time this happened silently)." >&2
  exit 1
fi
