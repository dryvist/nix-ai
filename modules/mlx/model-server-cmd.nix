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

  # Per-model backend resolution.
  backendFor = modelId: cfg.modelBackends.${modelId} or cfg.modelServerBackend;

  # Build the selected serving command for a given model ID.
  # Global option values may be replaced per physical model via
  # modelFlagOverrides; every override key must appear in overridableFlags —
  # the serve options this builder reads below. Guarding against that list
  # (not against programs.mlx as a whole) means a typo AND a real-but-unread
  # option name (e.g. huggingFaceHome, preload) both fail the eval instead of
  # silently keeping the global value. Catalog class profiles also set
  # paged-cache, batch-width, request-cap and idle-unload keys; mlx_lm reads
  # none of those, so they are accepted here and have no effect on the command.
  # NOTE: \${PORT} is a llama-swap template macro — must be escaped to prevent
  # Nix string interpolation from consuming it before the config is written.
  overridableFlags = [
    "host"
    "cacheMemoryMb"
    "prefillBatchSize"
    "autoUnloadIdleSeconds"
    "enablePrefixCaching"
    "pagedKvCache"
    "pagedCacheBlockSize"
    "maxNumSeqs"
    "maxTokens"
    "maxRequestTokens"
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
          # 16 slots: the fleet has roughly 8 Hermes profiles plus
          # Hindsight and interactive clients interleaving turns on the
          # 27B model, and a 4-slot cache measured hits at 4.7s versus
          # 98-154s misses re-prefilling roughly 20k tokens.
          "--prompt-cache-size"
          "16"
        ]
        ++
          # Reuse the backend-neutral cache budget. Official mlx_lm calls this
          # the prompt-cache byte limit.
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
          mlx-vlm = mlxVlmFlags;
          mlx-vlm-native = mlxVlmNativeFlags;
        }
        .${backend};
    in
    "${lib.getExe serverPkg} --model ${modelId} --port \${PORT} --host ${c.host}${
      lib.optionalString (mlxModelServerFlags != "") " ${mlxModelServerFlags}"
    }";

}
