# Shared per-backend worker environment — split from default.nix (12KB gate),
# same pattern as vllm-cmd.nix.
#
# Three of these carry settings that upstream vllm-mlx either has no CLI lever
# for, or accepts on the command line but then discards:
#
#   MLX_BUFFER_CACHE_LIMIT           caps MLX's retained free-buffer pool;
#                                    env-only upstream (see options-cache.nix)
#   VLLM_MLX_LOG_LEVEL               upstream hardcodes its log level
#   VLLM_MLX_GPU_MEMORY_UTILIZATION  the CLI flag is dropped on the lifecycle
#                                    engine path (autoUnloadIdleSeconds > 0)
#
# The latter two are read by the wheel patch in vllm-mlx-patch.nix, which
# documents each substitution and why it is needed.
{ lib, cfg }:
{
  workerEnv = [
    "HF_HOME=${cfg.huggingFaceHome}"
    "VLLM_MLX_LOG_LEVEL=${cfg.serverLogLevel}"
  ]
  ++ lib.optionals (cfg.bufferCacheLimitGb != null) [
    "MLX_BUFFER_CACHE_LIMIT=${toString (cfg.bufferCacheLimitGb * 1024 * 1024 * 1024)}"
  ]
  ++ lib.optionals (cfg.gpuMemoryUtilization != null) [
    "VLLM_MLX_GPU_MEMORY_UTILIZATION=${toString cfg.gpuMemoryUtilization}"
  ];
}
