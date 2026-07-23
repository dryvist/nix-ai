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
pkgs.writeShellScriptBin "mlx-lm-server" ''
  export MLX_L1_MEMORY_LIMIT_BYTES=${toString (cfg.memoryHardLimitGb * gib)}
  ${lib.optionalString (cfg.bufferCacheLimitGb != null)
    "export MLX_L1_CACHE_LIMIT_BYTES=${toString (cfg.bufferCacheLimitGb * gib)}"
  }
  exec ${pkgs.uv}/bin/uv run --python ${uvPythonVersion} --with "${mlxLmPin}" --with "${mlxPin}" --with "${transformersPin}" python ${./scripts/mlx-lm-launch.py} "$@"
''
