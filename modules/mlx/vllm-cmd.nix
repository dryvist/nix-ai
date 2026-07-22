# vllm-mlx serve-command builder — split from default.nix (12KB gate).
# See default.nix for how mkVllmCmd is consumed by the model builders.
{
  lib,
  cfg,
  vllmMlxPkg,
}:
rec {
  # Build the vllm-mlx serve command string for a given model ID.
  # Global option values may be replaced per physical model via
  # modelFlagOverrides; every override key must appear in overridableFlags —
  # the serve options this builder reads below. Guarding against that list
  # (not against programs.mlx as a whole) means a typo AND a real-but-unread
  # option name (e.g. huggingFaceHome, preload) both fail the eval instead of
  # silently keeping the global value.
  # NOTE: \${PORT} is a llama-swap template macro — must be escaped to prevent
  # Nix string interpolation from consuming it before the config is written.
  overridableFlags = [
    "host"
    "cacheMemoryMb"
    "prefillBatchSize"
    "gpuMemoryUtilization"
    "autoUnloadIdleSeconds"
    "enableMetrics"
    "continuousBatching"
    "defaultRepetitionPenalty"
    "enablePrefixCaching"
    "pagedKvCache"
    "pagedCacheBlockSize"
    "maxNumSeqs"
    "chunkedPrefillTokens"
    "completionBatchSize"
    "maxTokens"
    "maxRequestTokens"
    "enableAutoToolChoice"
    "toolCallParser"
    "reasoningParser"
  ];
  mkVllmCmd =
    modelId:
    let
      overrides = cfg.modelFlagOverrides.${modelId} or { };
      unknown = lib.filter (k: !(lib.elem k overridableFlags)) (lib.attrNames overrides);
      c =
        if unknown == [ ] then
          cfg // overrides
        else
          throw "programs.mlx.modelFlagOverrides.\"${modelId}\": not overridable serve option(s): ${lib.concatStringsSep ", " unknown}";
      textOnlyEnv = lib.optionalString (cfg.modelTextOnly.${modelId} or false
      ) "/usr/bin/env VLLM_MLX_FORCE_TEXT_ONLY=1 ";
      baseCmd = "${textOnlyEnv}${lib.getExe vllmMlxPkg} serve ${modelId} --port \${PORT} --host ${c.host}";
      flags = lib.concatStringsSep " " (
        lib.optionals (c.cacheMemoryMb != null) [
          "--cache-memory-mb"
          (toString c.cacheMemoryMb)
        ]
        ++ lib.optionals (c.prefillBatchSize != null) [
          "--prefill-batch-size"
          (toString c.prefillBatchSize)
        ]
        ++ lib.optionals (c.gpuMemoryUtilization != null) [
          "--gpu-memory-utilization"
          (toString c.gpuMemoryUtilization)
        ]
        ++ lib.optionals (c.autoUnloadIdleSeconds != 0) [
          "--auto-unload-idle-seconds"
          (toString c.autoUnloadIdleSeconds)
        ]
        ++ lib.optionals c.enableMetrics [ "--enable-metrics" ]
        ++ lib.optionals c.continuousBatching [ "--continuous-batching" ]
        # Applied server-side so every request carries the same logits
        # processor — a batch mixing penalized with penalty-free requests
        # wedges mlx_lm's generator. Rationale in options-batching.nix.
        ++ lib.optionals (c.defaultRepetitionPenalty != null) [
          "--default-repetition-penalty"
          (toString c.defaultRepetitionPenalty)
        ]
        ++ lib.optionals c.enablePrefixCaching [ "--enable-prefix-cache" ]
        ++ lib.optionals c.pagedKvCache [ "--use-paged-cache" ]
        ++ lib.optionals (c.pagedKvCache && c.pagedCacheBlockSize != null) [
          "--paged-cache-block-size"
          (toString c.pagedCacheBlockSize)
        ]
        ++ lib.optionals (c.maxNumSeqs != null) [
          "--max-num-seqs"
          (toString c.maxNumSeqs)
        ]
        ++ lib.optionals (c.chunkedPrefillTokens != null) [
          "--chunked-prefill-tokens"
          (toString c.chunkedPrefillTokens)
        ]
        ++ lib.optionals (c.completionBatchSize != null) [
          "--completion-batch-size"
          (toString c.completionBatchSize)
        ]
        ++ lib.optionals (c.maxTokens != null) [
          "--max-tokens"
          (toString c.maxTokens)
        ]
        ++ lib.optionals (c.maxRequestTokens != null) [
          "--max-request-tokens"
          (toString c.maxRequestTokens)
        ]
        ++ lib.optionals c.enableAutoToolChoice [ "--enable-auto-tool-choice" ]
        ++ lib.optionals (c.enableAutoToolChoice && c.toolCallParser != null) [
          "--tool-call-parser"
          c.toolCallParser
        ]
        ++ lib.optionals (c.reasoningParser != null) [
          "--reasoning-parser"
          c.reasoningParser
        ]
      );
    in
    "${baseCmd}${lib.optionalString (flags != "") " ${flags}"}";

}
