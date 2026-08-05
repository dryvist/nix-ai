# In-process launcher for the official mlx_lm.server (the L2 memory layer).
#
# mlx_lm.server has no memory-limit flag and MLX core does not read a
# memory-limit env var, so the only way to bound a worker below the OS wired
# ceiling is to set the limit in-process before serving. This wrapper sets the
# MLX allocation limit (mx.set_memory_limit) and the free-buffer cache limit
# (mx.set_cache_limit) from bytes passed in the environment, then hands off to
# the server's own entry point, which parses sys.argv exactly as before.
#
# Both limits are guidelines, not hard caps: MLX raises only when RAM+swap is
# genuinely exhausted (see docs.jacobpevans.com/local-llm/memory-ceilings). The
# real guarantee is structural — this budget sits below the wired ceiling, which
# sits below physical RAM with the OS reserve. This just makes MLX shed cache
# and fail allocation ahead of the wired ceiling instead of at 1.5x it (the MLX
# default), so pressure surfaces as an application error, not host-wide swap.
import inspect
import os

import mlx.core as mx
import mlx_lm.server
from mlx_lm.server import main

_limit = os.environ.get("MLX_L1_MEMORY_LIMIT_BYTES")
if _limit:
    mx.set_memory_limit(int(_limit))

_cache = os.environ.get("MLX_L1_CACHE_LIMIT_BYTES")
if _cache:
    mx.set_cache_limit(int(_cache))

# Suppress the upstream wired-limit pin (ml-explore/mlx#3186, Apple
# FB22091885). mlx_lm.server calls mx.set_wired_limit(max_recommended_working_
# set_size) unconditionally inside main(), with no flag to disable it. Pinning
# the whole recommended working set is the discriminating variable for an
# IOGPUFamily "completeMemory() prepare count underflow" kernel panic: upstream
# isolated it single-variable at ~100 s to panic with the call under
# prompt-cache eviction churn, versus ~9 h / 5.3M tokens clean without it.
#
# mx.set_wired_limit PINS memory resident; it is not a cap. The real ceiling is
# the host sysctl iogpu.wired_limit_mb. Suppressing this leaves MLX at its
# default of 0 (nothing pinned), which makes weights pageable — so the residency
# budget k_max x L1_mem <= wired ceiling must hold, or this trades a panic for
# swap thrash. See modules/mlx/options-residency.nix.
if os.environ.get("MLX_SUPPRESS_WIRED_LIMIT") == "1":
    # Fail closed if upstream moves or renames the call site. A silently
    # non-intercepting shim reintroduces the kernel panic, so a hard error at
    # worker start is the safer failure: it is immediate and visible, where the
    # alternative is an unrecoverable host crash under load.
    if "mx.set_wired_limit(" not in inspect.getsource(mlx_lm.server):
        raise RuntimeError(
            "MLX_SUPPRESS_WIRED_LIMIT=1 but mlx_lm.server no longer calls "
            "mx.set_wired_limit(). The upstream call site changed shape. "
            "Re-check ml-explore/mlx#3186 before removing this shim — if "
            "upstream fixed the panic, drop the option; if it merely moved, "
            "update this guard."
        )

    def _suppress_wired_limit(nbytes):
        # Printed so interception is provable from the worker log rather than
        # assumed.
        print(
            f"mlx-lm-launch: suppressed mx.set_wired_limit({nbytes}) "
            "— see ml-explore/mlx#3186",
            flush=True,
        )
        return 0

    mx.set_wired_limit = _suppress_wired_limit

main()
