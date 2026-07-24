# MLX model-server command builder — split from default.nix (12KB gate).
{
  lib,
  cfg,
  mlxModelServerPkg,
}:
rec {
  # Build the selected serving command for a given model ID.
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
  mkModelCmd =
    modelId:
    let
      backend = cfg.modelServerBackend;
      overrides = cfg.modelFlagOverrides.${modelId} or { };
      unknown = lib.filter (k: !(lib.elem k overridableFlags)) (lib.attrNames overrides);
      c =
        if unknown == [ ] then
          cfg // overrides
        else
          throw "programs.mlx.modelFlagOverrides.\"${modelId}\": not overridable serve option(s): ${lib.concatStringsSep ", " unknown}";
      effectiveMlxLmMaxTokens = if c.maxTokens == null then 8192 else c.maxTokens;
      # Honor the configured prompt-cache budget up to 16 GiB. The prior 8 GiB
      # clamp silently capped catalog entries that ask for more (e.g. the
      # large-context resident class at cacheMemoryMb = 16384), making the
      # documented 16 GiB prefill-reuse story false. 16 GiB stays well inside
      # the 99 GiB L2 budget on the 128 GiB Macs.
      effectiveMlxLmCacheMb = if c.cacheMemoryMb == null then 8192 else lib.min c.cacheMemoryMb 16384;
      mlxLmLogLevel =
        {
          debug = "DEBUG";
          info = "INFO";
          warn = "WARNING";
          error = "ERROR";
        }
        .${cfg.serverLogLevel};
      vllmMlxFlags = lib.concatStringsSep " " (
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
      mlxLmFlags = lib.concatStringsSep " " (
        [
          "--log-level"
          mlxLmLogLevel
          "--max-tokens"
          (toString effectiveMlxLmMaxTokens)
          "--decode-concurrency"
          "1"
          "--prompt-concurrency"
          "1"
          # 4 slots, not 1: multiple clients interleaving turns evict each
          # other's cache at size 1 (measured 0.22s warm vs 8.34s cold after
          # one intervening conversation — a 38x penalty at 7k tokens).
          "--prompt-cache-size"
          "4"
        ]
        ++
          # Reuse the backend-neutral cache budget. Official mlx_lm calls this
          # the prompt-cache byte limit; vllm-mlx calls it cache memory in MiB.
          # Bounded at 16 GiB (effectiveMlxLmCacheMb above) so large-context
          # catalog classes get the cache they declare.
          [
            "--prompt-cache-bytes"
            (toString (effectiveMlxLmCacheMb * 1024 * 1024))
          ]
        ++ lib.optionals (c.prefillBatchSize != null) [
          "--prefill-step-size"
          (toString c.prefillBatchSize)
        ]
      );
      mlxModelServerFlags =
        {
          mlx-lm = mlxLmFlags;
          vllm-mlx = vllmMlxFlags;
        }
        .${backend};
    in
    "${lib.getExe mlxModelServerPkg} --model ${modelId} --port \${PORT} --host ${c.host}${
      lib.optionalString (mlxModelServerFlags != "") " ${mlxModelServerFlags}"
    }";

}
