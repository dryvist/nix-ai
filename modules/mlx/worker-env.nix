# Shared per-backend worker environment — split from default.nix (12KB gate),
# same pattern as the command builder.
# MLX_BUFFER_CACHE_LIMIT is exported for the record; MLX core has no such env
# var, so under mlx-lm the buffer-cache cap is enforced in-process via
# mx.set_cache_limit in the launcher (scripts/mlx-lm-launch.py).
{ lib, cfg }:
let
  shared = [
    "HF_HOME=${cfg.huggingFaceHome}"
    # Models are fully cached under HF_HOME; loads must never depend on
    # reaching huggingface.co at serve time.
    "HF_HUB_OFFLINE=1"
  ]
  ++ lib.optionals (cfg.bufferCacheLimitGb != null) [
    "MLX_BUFFER_CACHE_LIMIT=${toString (cfg.bufferCacheLimitGb * 1024 * 1024 * 1024)}"
  ];
  mlxModelServerEnvironments = {
    mlx-lm = shared;
    mlx-vlm = shared;
    mlx-vlm-native = shared;
  };
in
{
  workerEnv =
    modelId:
    let
      backend = cfg.modelBackends.${modelId} or cfg.modelServerBackend;
      mtp =
        cfg.modelMtpProfiles.${modelId} or {
          enable = false;
          tokenQueueTimeoutSeconds = 1800;
        };
    in
    mlxModelServerEnvironments.${backend}
    ++ lib.optionals (backend == "mlx-vlm-native" && mtp.enable) [
      "MLX_VLM_TOKEN_QUEUE_TIMEOUT=${toString mtp.tokenQueueTimeoutSeconds}"
    ];
}
