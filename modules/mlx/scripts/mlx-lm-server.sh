# shellcheck shell=bash
# mlx_lm.server wrapper carrying the in-process L2 memory limit.
#
# mlx_lm.server has no memory-limit flag, so the worker goes through
# mlx-lm-launch.py, which sets mx.set_memory_limit + mx.set_cache_limit before
# serving and then hands off to the server's own argv-parsing entry point.
# Those limits arrive as environment variables; see mlx-lm-launch.py.
#
# The at-sign-delimited names below are substituted at build time by
# pkgs.replaceVars in ../mlx-lm-server.nix — this file is not runnable as-is,
# and replaceVars fails the build if any of them survives unsubstituted.
#
# The python here is a Nix store env holding mlx (Metal wheel), the
# harmony-patched mlx-lm, and transformers as one atomic set. It used to be
# `uv run --with ...`, which minted a fresh ~1.4 GB venv per resolution and
# never evicted one. Execing python directly also removes a process layer:
# llama-swap -> python, not llama-swap -> uv run -> python.

export MLX_L1_MEMORY_LIMIT_BYTES="@memoryLimitBytes@"

# Empty when programs.mlx.bufferCacheLimitGb is null — leave the variable
# unset in that case so the launcher keeps mlx's own default rather than
# reading an empty string as a limit.
cacheLimitBytes="@cacheLimitBytes@"
if [ -n "$cacheLimitBytes" ]; then
  export MLX_L1_CACHE_LIMIT_BYTES="$cacheLimitBytes"
fi

# Bound to a variable rather than compared inline: after substitution an inline
# test reads as a constant expression and shellcheck fails the build (SC2050).
suppressWiredLimit="@suppressWiredLimit@"
if [ "$suppressWiredLimit" = "1" ]; then
  export MLX_SUPPRESS_WIRED_LIMIT=1
fi

exec "@pythonEnv@/bin/python" "@launcher@" "$@"
