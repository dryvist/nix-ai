# Official mlx_lm.server wrappers carrying the in-process L2 memory limit.
# Split from default.nix for the 12 KB file-size gate. mlx_lm.server has no
# memory-limit flag, so the worker is launched through scripts/mlx-lm-launch.py,
# which sets mx.set_memory_limit + mx.set_cache_limit before serving and then
# hands off to the server's own argv-parsing entry point.
#
# TWO WRAPPERS, ONE SCRIPT. They differ in exactly one thing — which mlx-lm
# wheel uv resolves — so they are built from a single template rather than
# duplicated:
#
#   pkg     mlx-lm-server      release wheel, harmony-patched (mlx-lm-patch.nix)
#   gitPkg  mlx-lm-server-git  pinned git wheel (mlx-lm-git.nix)
#
# `pkg` is the default for everything. mlx-lm resolves from the harmony-patched
# wheel rather than the plain `mlx-lm==<version>` pin because upstream infers no
# tool parser for gpt-oss, so its harmony tool calls come back as raw markup
# inside `content` with `tool_calls: null`. See mlx-lm-patch.nix for the defect
# and the patch.
#
# `gitPkg` exists only because no mlx-lm release implements deepseek_v4. THE
# HARMONY PATCH IS NOT PORTED TO IT, so any model relying on harmony tool
# parsing must never resolve here — options-catalog.nix asserts that, and
# model-server-cmd.nix omits --harmony-tool-parser for this wrapper because the
# flag does not exist on it. Removal criterion: lib/versions.nix mlxLmGit.
{
  pkgs,
  lib,
  cfg,
  uvPythonVersion,
  mlxLmVersion,
  mlxLmGit,
  mlxPin,
  transformersPin,
}:
let
  gib = 1024 * 1024 * 1024;
  mlxLmWheel = import ./mlx-lm-patch.nix { inherit pkgs mlxLmVersion; };
  mlxLmGitWheel = import ./mlx-lm-git.nix { inherit pkgs mlxLmGit; };
  mkServer =
    name: wheel:
    pkgs.writeShellScriptBin name ''
      export MLX_L1_MEMORY_LIMIT_BYTES=${toString (cfg.memoryHardLimitGb * gib)}
      ${lib.optionalString (cfg.bufferCacheLimitGb != null)
        "export MLX_L1_CACHE_LIMIT_BYTES=${toString (cfg.bufferCacheLimitGb * gib)}"
      }
      ${lib.optionalString cfg.suppressWiredLimit "export MLX_SUPPRESS_WIRED_LIMIT=1"}
      exec ${pkgs.uv}/bin/uv run --python ${uvPythonVersion} --with "${wheel}" --with "${mlxPin}" --with "${transformersPin}" python ${./scripts/mlx-lm-launch.py} "$@"
    '';
in
{
  pkg = mkServer "mlx-lm-server" mlxLmWheel;
  gitPkg = mkServer "mlx-lm-server-git" mlxLmGitWheel;

  # Basename of the in-process launcher these wrappers exec into. Single
  # source that default.nix's modelServerProcessPattern.mlx-lm derives its
  # pgrep/pkill pattern from, so the pattern can never silently drift from
  # what the wrappers actually exec the way it did after this file's
  # mlx-lm-launch.py replaced a direct mlx_lm.server invocation (#1368) —
  # the pattern used to read "/mlx_lm\.server" and nobody updated it, so
  # every pgrep/pkill consumer (llama-swap-launch.sh's old reap,
  # mlx-watchdog.sh, mlx-status.sh, cluster-join.sh's quiesce reap) silently
  # matched nothing for months. See scripts/llama-swap-reap.sh for the
  # measured incident. BOTH wrappers exec the same launcher, so one pattern
  # still covers every worker.
  launchScriptBasename = builtins.baseNameOf (toString ./scripts/mlx-lm-launch.py);
}
