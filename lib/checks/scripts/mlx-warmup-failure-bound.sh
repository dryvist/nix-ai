#!/usr/bin/env bash
# Test body for the mlx-warmup-failure-bound check (lib/checks/mlx-warmup.nix).
# Extracted to its own file per this repo's inline-script policy for .nix
# files. MLX_WARMUP_SCRIPT and the MLX_WARMUP_* / MLX_* env vars are set by
# the calling derivation; $out and $TMPDIR come from the Nix build env.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"

python3 "$MLX_WARMUP_SCRIPT" > "$TMPDIR/run1.log" 2>&1 && exit1=0 || exit1=$?
test "$exit1" -eq 1
test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 1
grep -q 'WARMUP FAILED (1/3 consecutive)' "$TMPDIR/run1.log"

python3 "$MLX_WARMUP_SCRIPT" > "$TMPDIR/run2.log" 2>&1 && exit2=0 || exit2=$?
test "$exit2" -eq 1
test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 2
grep -q 'WARMUP FAILED (2/3 consecutive)' "$TMPDIR/run2.log"

# THE regression this check guards: the 3rd consecutive failure must give up
# (exit 0) rather than restart forever. An unbounded/reverted restart loop
# would exit 1 here too, and this assertion would fail.
python3 "$MLX_WARMUP_SCRIPT" > "$TMPDIR/run3.log" 2>&1 && exit3=0 || exit3=$?
test "$exit3" -eq 0
test ! -e "$MLX_WARMUP_FAIL_MARKER"
grep -q 'WARMUP GIVING UP after 3 consecutive failed cycles' "$TMPDIR/run3.log"

# A give-up is a resolved outcome, not a permanent one: the next legitimate
# trigger (e.g. after a real proxy restart) gets a fresh budget instead of
# starting pre-exhausted.
python3 "$MLX_WARMUP_SCRIPT" > "$TMPDIR/run4.log" 2>&1 && exit4=0 || exit4=$?
test "$exit4" -eq 1
test "$(<"$MLX_WARMUP_FAIL_MARKER")" = 1

touch "$out"
