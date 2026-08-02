#!/usr/bin/env bash
# Test body for the mlx-warmup-min-interval check (lib/checks/mlx-warmup.nix).
# Extracted to its own file per this repo's inline-script policy for .nix
# files. MLX_WARMUP_SCRIPT and the MLX_WARMUP_* / MLX_* env vars are set by
# the calling derivation; $out and $TMPDIR come from the Nix build env.
#
# Deterministic contract for the re-invocation bound (the kickstart-bypass
# gap): `launchctl kickstart -k` bypasses ThrottleInterval entirely, so
# something that calls it in a tight loop (observed: cluster-link-watcher.sh
# re-triggering restore_normal_serving() on every failed rendezvous cycle)
# must not be able to make mlx-warmup.py re-acquire the preloaded model's
# llama-swap concurrency slot on every single call. MLX_WARMUP_MIN_INTERVAL_SECONDS
# bounds that independent of the failure-streak logic in mlx-warmup-failure-bound.sh
# and independent of exit status. See mlx-warmup.py's RE-INVOCATION BOUND.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"

# 1st invocation: no marker yet, so it proceeds and (API unreachable) fails
# the cycle normally, stamping both markers.
python3 "$MLX_WARMUP_SCRIPT" > "$TMPDIR/run1.log" 2>&1 && exit1=0 || exit1=$?
test "$exit1" -eq 1
test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 1
test -e "$MLX_WARMUP_LAST_ATTEMPT_MARKER"

# THE regression this check guards: an immediate re-invocation (simulating an
# external kickstart -k storm) must be skipped rather than attempted — exit
# 0, no HTTP attempt, and critically the failure streak is left untouched (a
# skip is not a failure and must not be conflated with one).
python3 "$MLX_WARMUP_SCRIPT" > "$TMPDIR/run2.log" 2>&1 && exit2=0 || exit2=$?
test "$exit2" -eq 0
test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 1
grep -q 'Skipping warm attempt' "$TMPDIR/run2.log"

# Once the interval has elapsed (simulated by backdating the marker rather
# than sleeping, to keep this check fast), the next invocation must proceed
# normally again.
echo "0" > "$MLX_WARMUP_LAST_ATTEMPT_MARKER"
python3 "$MLX_WARMUP_SCRIPT" > "$TMPDIR/run3.log" 2>&1 && exit3=0 || exit3=$?
test "$exit3" -eq 1
test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 2
grep -q 'WARMUP FAILED (2/3 consecutive)' "$TMPDIR/run3.log"

touch "$out"
