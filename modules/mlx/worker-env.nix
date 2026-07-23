# Shared per-backend worker environment — split from default.nix (12KB gate),
# same pattern as the command builder.
# MLX_BUFFER_CACHE_LIMIT is an official MLX runtime control. vllm-mlx-specific
# environment variables are intentionally absent because that backend is disabled.
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
