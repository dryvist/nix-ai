# Official mlx_lm.server wrapper carrying the in-process L2 memory limit.
# Split from default.nix for the 12 KB file-size gate. mlx_lm.server has no
# memory-limit flag, so the worker is launched through scripts/mlx-lm-launch.py,
# which sets mx.set_memory_limit + mx.set_cache_limit before serving and then
# hands off to the server's own argv-parsing entry point. GiB option values
# become bytes here and are passed in the environment.
{
  pkgs,
  lib,
  cfg,
  uvPythonVersion,
  mlxLmPin,
  mlxPin,
  transformersPin,
}:
let
  gib = 1024 * 1024 * 1024;
in
{
  pkg = pkgs.writeShellScriptBin "mlx-lm-server" ''
    export MLX_L1_MEMORY_LIMIT_BYTES=${toString (cfg.memoryHardLimitGb * gib)}
    ${lib.optionalString (cfg.bufferCacheLimitGb != null)
      "export MLX_L1_CACHE_LIMIT_BYTES=${toString (cfg.bufferCacheLimitGb * gib)}"
    }
    exec ${pkgs.uv}/bin/uv run --python ${uvPythonVersion} --with "${mlxLmPin}" --with "${mlxPin}" --with "${transformersPin}" python ${./scripts/mlx-lm-launch.py} "$@"
  '';

  # Basename of the in-process launcher this wrapper execs into. Single
  # source that default.nix's modelServerProcessPattern.mlx-lm derives its
  # pgrep/pkill pattern from, so the pattern can never silently drift from
  # what this wrapper actually execs the way it did after this file's
  # mlx-lm-launch.py replaced a direct mlx_lm.server invocation (#1368) —
  # the pattern used to read "/mlx_lm\.server" and nobody updated it, so
  # every pgrep/pkill consumer (llama-swap-launch.sh's old reap,
  # mlx-watchdog.sh, mlx-status.sh, cluster-join.sh's quiesce reap) silently
  # matched nothing for months. See scripts/llama-swap-reap.sh for the
  # measured incident.
  launchScriptBasename = builtins.baseNameOf (toString ./scripts/mlx-lm-launch.py);
}
