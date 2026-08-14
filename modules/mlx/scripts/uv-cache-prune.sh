#!/usr/bin/env bash
# Reclaim unreachable objects from the uv cache, at activation time.
#
# Why this exists: every distinct `uv run --with` / `uvx` resolution in this
# module materializes a COMPLETE venv under ~/.cache/uv/archive-v0 (torch + mlx
# + pyarrow + cv2 ~= 1.4 GB each, hardlink count 1 — no sharing between them).
# uv never evicts them, so each pinned-set bump strands the previous venv
# forever. Observed 2026-08-14 on jevans-mbp: 328 GB of cache, 3980 archive
# entries of which only ~1140 were still referenced by environments-v2.
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

if pgrep -qf 'mlx-lm-launch'; then
  echo "mlx: uv cache prune skipped — a model is loaded. Runs on the next rebuild with nothing loaded." >&2
  exit 0
fi

dir=$("$UV" cache dir)
before=$(du -sk "$dir" 2>/dev/null | cut -f1 || echo 0)
if ! "$UV" cache prune --force >/dev/null 2>&1; then
  echo "mlx: uv cache prune failed (non-fatal); cache left as-is." >&2
  exit 0
fi
after=$(du -sk "$dir" 2>/dev/null | cut -f1 || echo 0)
echo "mlx: uv cache pruned, reclaimed $(((before - after) / 1024)) MiB."
