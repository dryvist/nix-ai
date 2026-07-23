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
import os

import mlx.core as mx
from mlx_lm.server import main

_limit = os.environ.get("MLX_L1_MEMORY_LIMIT_BYTES")
if _limit:
    mx.set_memory_limit(int(_limit))

_cache = os.environ.get("MLX_L1_CACHE_LIMIT_BYTES")
if _cache:
    mx.set_cache_limit(int(_cache))

main()
