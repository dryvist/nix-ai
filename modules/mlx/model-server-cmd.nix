# MLX model-server command builder — split from default.nix (12KB gate).
{
  lib,
  cfg,
  mlxModelServerPkg,
  # Per-backend server packages, for models whose backend differs from the
  # host's. Optional and empty by default so callers that only ever serve the
  # host backend (lib/checks) keep working unchanged; any backend missing here
  # falls back to mlxModelServerPkg.
  mlxModelServerPkgs ? { },
}:
rec {
  # SINGLE DEFINITION of per-model concurrency. Both consumers derive from it:
  # llama-swap's advertised `concurrencyLimit` (default.nix registryModels) and
  # the MLX server's own --decode-concurrency/--prompt-concurrency below.
  # These were two independent values — the flags were hard-coded "1" while the
  # proxy default is 4 — so llama-swap admitted 4 requests to a server serving
  # 1, and the excess came back as HTTP 429 (2026-07-24 cron kills).
  effectiveConcurrency = modelId: cfg.modelConcurrencyLimits.${modelId} or cfg.proxy.concurrencyLimit;

  # Per-model backend resolution, exported so mkModelCmd and model-instances.nix
  # share one answer: the latter needs it to decide how the catalog's
  # backend-neutral extraArgs must be spelled for that backend, and a second
  # copy of the `or` chain there would drift from the flag builder it must agree
  # with. worker-env.nix and assertions.nix still inline the same expression —
  # folding those in is a separate change, not part of this fix.
  backendFor = modelId: cfg.modelBackends.${modelId} or cfg.modelServerBackend;

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
    "harmonyToolParser"
  ];
  mkModelCmd =
    modelId:
    let
      backend = backendFor modelId;
      mtp =
        cfg.modelMtpProfiles.${modelId} or {
          enable = false;
          drafterModel = null;
          maxKvTokens = 131072;
          maxNumSeqs = 1;
          tokenQueueTimeoutSeconds = 1800;
          draftBlockSize = null;
        };
      serverPkg = mlxModelServerPkgs.${backend} or mlxModelServerPkg;
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
        ++ lib.optionals mtp.enable [ "--enable-mtp" ]
        ++ lib.optionals (mtp.enable && mtp.draftBlockSize != null) [
          "--draft-block-size"
          (toString mtp.draftBlockSize)
        ]
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
          (toString (effectiveConcurrency modelId))
          "--prompt-concurrency"
          (toString (effectiveConcurrency modelId))
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
        # Flag added by the harmony-patched wheel (mlx-lm-patch.nix). Always
        # emitted so the deployed command states the mode instead of leaving it
        # to a package-side default.
        ++ [
          "--harmony-tool-parser"
          c.harmonyToolParser
        ]
      );
      # mlx_vlm.server shares only --model/--port/--host with mlx_lm.server;
      # none of the mlx-lm tuning flags above exist on it, so this set stays
      # deliberately bare rather than reusing mlxLmFlags. Idle unload is not a
      # worker flag here either — mlx_vlm.server has none, so llama-swap's
      # proxy-side ttl is the only eviction path (see modelTtls).
      # --trust-remote-code: the vision OCR architectures this backend exists to
      # serve ship custom modelling code. Weights are already resolved from the
      # local HF cache with HF_HUB_OFFLINE=1 (worker-env.nix), so this executes
      # pinned on-disk code, never anything fetched at serve time.
      mlxVlmFlags = "--trust-remote-code";
      mlxVlmNativeFlags = lib.concatStringsSep " " (
        [
          "--trust-remote-code"
          "--max-tokens"
          (toString effectiveMlxLmMaxTokens)
          "--max-kv-size"
          (toString mtp.maxKvTokens)
        ]
        ++ lib.optionals mtp.enable [
          "--draft-model"
          mtp.drafterModel
          "--draft-kind"
          "mtp"
          "--max-num-seqs"
          (toString mtp.maxNumSeqs)
        ]
        ++ lib.optionals (mtp.enable && mtp.draftBlockSize != null) [
          "--draft-block-size"
          (toString mtp.draftBlockSize)
        ]
      );
      mlxModelServerFlags =
        {
          mlx-lm = mlxLmFlags;
          vllm-mlx = vllmMlxFlags;
          mlx-vlm = mlxVlmFlags;
          mlx-vlm-native = mlxVlmNativeFlags;
        }
        .${backend};
    in
    "${lib.getExe serverPkg} --model ${modelId} --port \${PORT} --host ${c.host}${
      lib.optionalString (mlxModelServerFlags != "") " ${mlxModelServerFlags}"
    }";

}
