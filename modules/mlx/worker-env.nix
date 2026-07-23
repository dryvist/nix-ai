# Shared per-backend worker environment — split from default.nix (12KB gate),
# same pattern as the command builder.
# MLX_BUFFER_CACHE_LIMIT is exported for backends that read it (the preserved
# vllm-mlx path). MLX core itself has no such env var, so under mlx-lm the
# buffer-cache cap is enforced in-process instead, via mx.set_cache_limit in
# the launcher (scripts/mlx-lm-launch.py). vllm-mlx-specific environment
# variables are otherwise absent because that backend is disabled.
{ lib, cfg }:
let
  shared = [
    "HF_HOME=${cfg.huggingFaceHome}"
  ]
  ++ lib.optionals (cfg.bufferCacheLimitGb != null) [
    "MLX_BUFFER_CACHE_LIMIT=${toString (cfg.bufferCacheLimitGb * 1024 * 1024 * 1024)}"
  ];
  mlxModelServerEnvironments = {
    mlx-lm = shared;
    vllm-mlx =
      shared
      ++ [
        "VLLM_MLX_LOG_LEVEL=${cfg.serverLogLevel}"
      ]
      ++ lib.optionals (cfg.gpuMemoryUtilization != null) [
        "VLLM_MLX_GPU_MEMORY_UTILIZATION=${toString cfg.gpuMemoryUtilization}"
      ];
  };
in
{
  workerEnv = mlxModelServerEnvironments.${cfg.modelServerBackend};
}
