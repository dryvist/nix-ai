#!/usr/bin/env bash
# Reclaim unreachable objects from the uv cache, at activation time.
#
# Why this exists: every distinct `uv run --with` / `uvx` resolution in this
# module materializes a COMPLETE venv under ~/.cache/uv/archive-v0 (torch + mlx
# + pyarrow + cv2 ~= 1.4 GB each, hardlink count 1 — no sharing between them).
# uv never evicts them, so each pinned-set bump strands the previous venv
# forever, and an unpruned cache grows without bound. Measured at 328 GB of
# cache, 3980 archive entries, of which only ~1140 were still referenced by
# environments-v2.
#
# Why activation and not a launchd agent: a rebuild is an operator-initiated
# change with someone watching it. A timer firing on its own is not, and this
# host already has more background agents than it wants.
#
# Why --force: uvx-launched MCP servers are long-lived (days) and each holds a
# shared lock on the cache for its whole lifetime, so plain `prune` never wins
# the exclusive lock — it burns the 300 s timeout and exits having freed
# nothing. That is exactly how the cache reached 328 GB unnoticed. --force
# skips the in-use *lock* check only; reachability is still computed from the
# cache's own bookkeeping, so an env backing a live process is never a
# candidate for removal.
#
# Why the mlx guard: a loaded worker's interpreter lives in
# ~/.cache/uv/builds-v0, which --force will collect. Pruning underneath it
# breaks the running model on its next lazy import. llama-swap would respawn
# it, but a rebuild should not hand the operator a mid-request failure — skip
# instead, and let the next rebuild with nothing loaded collect it.
set -euo pipefail

UV="${1:?uv binary path required}"

# Absolute path on purpose. home-manager activation runs with a minimal PATH
# that does NOT include pgrep, and the first version of this guard called it
# bare. `set -e` does not fire on a failing `if` condition, so a missing pgrep
# made the test simply false and the script pruned ANYWAY, with a model loaded
# — the exact case the guard exists to prevent. Caught by an activation run,
# not by any static check. Darwin's procps package ships only ps/sysctl/top/
# watch, so the system binary is the right source here (same reasoning as
# llama-swap-reap.sh calling lsof/kill by absolute path).
PGREP=/usr/bin/pgrep

# Fail CLOSED. If the state cannot be determined, skip: a missed prune costs
# disk that the next rebuild reclaims, while pruning under a live worker pulls
# the interpreter out from under it (--force collects builds-v0).
if [ ! -x "$PGREP" ]; then
  echo "mlx: uv cache prune skipped — $PGREP is missing, so a loaded model cannot be ruled out." >&2
  exit 0
fi

if "$PGREP" -qf 'mlx-lm-launch'; then
  echo "mlx: uv cache prune skipped — a model is loaded. Runs on the next rebuild with nothing loaded." >&2
  exit 0
fi

dir=$("$UV" cache dir)
before=$(du -sk "$dir" 2>/dev/null | cut -f1 || echo 0)

# Capture rather than discard. The first version sent both streams to
# /dev/null, so a real failure printed only "prune failed" with no cause —
# reproducing in miniature the exact defect this whole hook exists to fix
# (`uv cache prune` reporting success while doing nothing). uv's own message is
# the only thing that says WHY, so it must reach the activation log.
#
# A known cause worth recognising: "failed to remove file ... (os error 2)"
# means the cache's bookkeeping references a file that is gone, usually after
# an interrupted prune. uv aborts the whole run on it. Clearing the archive
# entry named in the message lets the next prune proceed.
if ! prune_output=$("$UV" cache prune --force 2>&1); then
  echo "mlx: uv cache prune failed (non-fatal); cache left as-is:" >&2
  echo "$prune_output" | tail -3 >&2
  exit 0
fi

after=$(du -sk "$dir" 2>/dev/null | cut -f1 || echo 0)
echo "mlx: uv cache pruned, reclaimed $(((before - after) / 1024)) MiB."
