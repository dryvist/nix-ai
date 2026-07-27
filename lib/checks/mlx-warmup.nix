# Deterministic contract for the warmup restart-livelock fix: a warmup cycle
# that can never reach the API (unreachable here) must give up after
# MLX_WARMUP_MAX_CONSECUTIVE_FAILURES consecutive cycles by exiting 0 — which
# KeepAlive.SuccessfulExit=false in launchd.nix reads as "stop restarting" —
# instead of exiting 1 forever and re-acquiring the model's llama-swap
# concurrency slot on every restart. See modules/mlx/scripts/mlx-warmup.py.
{ pkgs, src }:
{
  mlx-warmup-failure-bound = pkgs.runCommand "check-mlx-warmup-failure-bound" { } ''
    export PATH=${pkgs.python3}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
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

    python3 ${src}/modules/mlx/scripts/mlx-warmup.py > "$TMPDIR/run1.log" 2>&1 && exit1=0 || exit1=$?
    test "$exit1" -eq 1
    test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 1
    grep -q 'WARMUP FAILED (1/3 consecutive)' "$TMPDIR/run1.log"

    python3 ${src}/modules/mlx/scripts/mlx-warmup.py > "$TMPDIR/run2.log" 2>&1 && exit2=0 || exit2=$?
    test "$exit2" -eq 1
    test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 2
    grep -q 'WARMUP FAILED (2/3 consecutive)' "$TMPDIR/run2.log"

    # THE regression this check guards: the 3rd consecutive failure must give
    # up (exit 0) rather than restart forever. An unbounded/reverted restart
    # loop would exit 1 here too, and this assertion would fail.
    python3 ${src}/modules/mlx/scripts/mlx-warmup.py > "$TMPDIR/run3.log" 2>&1 && exit3=0 || exit3=$?
    test "$exit3" -eq 0
    test ! -e "$MLX_WARMUP_FAIL_MARKER"
    grep -q 'WARMUP GIVING UP after 3 consecutive failed cycles' "$TMPDIR/run3.log"

    # A give-up is a resolved outcome, not a permanent one: the next
    # legitimate trigger (e.g. after a real proxy restart) gets a fresh
    # budget instead of starting pre-exhausted.
    python3 ${src}/modules/mlx/scripts/mlx-warmup.py > "$TMPDIR/run4.log" 2>&1 && exit4=0 || exit4=$?
    test "$exit4" -eq 1
    test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 1

    touch "$out"
  '';
}
