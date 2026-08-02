# Deterministic contracts for the warmup restart-livelock fix and its
# re-invocation bound. Test bodies live in ./scripts/ per this repo's
# inline-script policy for .nix files; each script's own header explains
# what it guards. See modules/mlx/scripts/mlx-warmup.py.
{ pkgs, src }:
{
  mlx-warmup-failure-bound = pkgs.runCommand "check-mlx-warmup-failure-bound" { } ''
    export PATH=${pkgs.python3}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export MLX_WARMUP_SCRIPT=${src}/modules/mlx/scripts/mlx-warmup.py
    # Port 1 is a reserved/privileged port nothing will ever have bound, so
    # this connection refuses instantly on any host regardless of sandbox
    # network policy — a fast, deterministic stand-in for "proxy unreachable".
    export MLX_API_URL="http://127.0.0.1:1/v1"
    export MLX_PRELOAD_MODELS_JSON='["test-model"]'
    export MLX_WARMUP_FAIL_MARKER="$TMPDIR/warmup-failures"
    # timeout=0 means the deadline is already "now" on the very first probe
    # inside wait_for_api, so every cycle fails immediately with no real
    # sleep — keeps this check fast instead of timing-dependent.
    export MLX_WARMUP_TIMEOUT_SECONDS=0
    export MLX_WARMUP_MAX_CONSECUTIVE_FAILURES=3
    # This check exercises the failure-streak bound with 4 back-to-back
    # invocations by design; the separate min-interval bound (tested in
    # mlx-warmup-min-interval below) would otherwise skip runs 2-4 and this
    # check would stop testing anything.
    export MLX_WARMUP_LAST_ATTEMPT_MARKER="$TMPDIR/warmup-last-attempt"
    export MLX_WARMUP_MIN_INTERVAL_SECONDS=0
    ${pkgs.bash}/bin/bash ${./scripts/mlx-warmup-failure-bound.sh}
  '';

  mlx-warmup-min-interval = pkgs.runCommand "check-mlx-warmup-min-interval" { } ''
    export PATH=${pkgs.python3}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export MLX_WARMUP_SCRIPT=${src}/modules/mlx/scripts/mlx-warmup.py
    export MLX_API_URL="http://127.0.0.1:1/v1"
    export MLX_PRELOAD_MODELS_JSON='["test-model"]'
    export MLX_WARMUP_FAIL_MARKER="$TMPDIR/warmup-failures"
    export MLX_WARMUP_LAST_ATTEMPT_MARKER="$TMPDIR/warmup-last-attempt"
    export MLX_WARMUP_TIMEOUT_SECONDS=0
    export MLX_WARMUP_MAX_CONSECUTIVE_FAILURES=3
    # A large window so the immediate 2nd invocation is unambiguously inside
    # it regardless of how long this check's own steps take to run.
    export MLX_WARMUP_MIN_INTERVAL_SECONDS=1000
    ${pkgs.bash}/bin/bash ${./scripts/mlx-warmup-min-interval.sh}
  '';
}
