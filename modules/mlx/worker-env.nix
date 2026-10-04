{
  lib,
  cfg,
}:
let
  shared = {
    HF_HOME = cfg.huggingFaceHome;
    HF_HUB_OFFLINE = "1";
  };
in
{
  workerEnv =
    modelId:
    let
      backend = cfg.modelBackends.${modelId} or cfg.modelServerBackend;
      mtp = cfg.modelMtpProfiles.${modelId} or { enable = false; };
    in
    shared
    // lib.optionalAttrs (backend == "mlx-vlm-native" && mtp.enable) {
      MLX_VLM_TOKEN_QUEUE_TIMEOUT = toString mtp.tokenQueueTimeoutSeconds;
    };
}
