#
# MLX Module — KV cache and prefill options
#
# vllm-mlx PERFORMANCE TUNING. Sizing target: M4 Max 128 GB.
#
# The wired ceiling is per-host and set OUTSIDE this module, by nix-darwin's
# system.appleSiliconTunables.wiredLimitMb. Every value here is sized against
# that ceiling, not against physical RAM.
# https://docs.jacobpevans.com/local-llm/memory-ceilings
#
# vllm-mlx 0.2.9 adds Paged KV Cache + prefix sharing on top of the
# memory-aware cache that auto-sizes based on available RAM.
#
# Cache-size rationale (cacheMemoryMb default = 8192):
#   The KV cache working set is bounded by maxNumSeqs * maxTokens * 2 (K and V)
#   times the per-layer state. For the Qwen3.x MoE models in this registry, 4
#   active sequences at 8192 tokens fit comfortably in 6-8 GB. The default of
#   8192 MB covers that plus prefix-cache headroom. Larger reservations just
#   wire memory that is never used.
#
# History note (2026-05-13): the previous default of 32768 MB combined with
# hot-swap activity drove the host into 24 GB of swap and ~1 tok/s decode on
# the flagship model. Lowering to 8192 restores expected throughput. Raise on
# a per-host basis if a workload genuinely benefits from larger cache; do not
# raise the module default.
#
{ lib, ... }:
{
  options.programs.mlx = {
    # cacheMemoryMb — Override the memory-aware cache size (--cache-memory-mb).
    # Default: 8192 (8 GB). Right-sized for maxNumSeqs=4 at maxTokens=8192 with
    # prefix-cache headroom; see the file-header rationale (lines 11-22) for
    # why the previous 32768 (32 GB) default was lowered.
    # Set to null to restore server auto-detect (~20% RAM = ~25.6 GB on 128 GB).
    # Ref: https://github.com/ml-explore/mlx-lm/issues/883
    cacheMemoryMb = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 8192;
      description = "KV cache reservation in MB (vllm-mlx --cache-memory-mb). Null = server auto-detect. Default 8 GB right-sized for maxNumSeqs=4 and maxTokens=8192; raise per-host if a workload needs more.";
    };

    # gpuMemoryUtilization — a device fraction, NOT the share of the host given
    # to inference (that is appleSiliconTunables.wiredLimitMb). It both caps each
    # worker and places the engine's emergency KV-clear trip point, so it is
    # coupled to the host ceiling and the two must be changed together.
    # Sizing rules, the invariant, and the re-derivation formula:
    # https://docs.jacobpevans.com/local-llm/memory-ceilings
    #
    # This is the per-worker enforcement layer that HardResourceLimits could not
    # provide (see launchd.nix) because it acts inside the worker process itself.
    # Ref: https://github.com/ml-explore/mlx-lm/issues/883
    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.nullOr (lib.types.numbers.between 0.05 1.0);
      default = 0.8;
      description = "Fraction of device memory each worker may allocate via Metal (vllm-mlx --gpu-memory-utilization), also used as the emergency cache-clear trip point at device_mem*(util+0.05). Coupled to the host wired ceiling — the invariant is footprint < trip < ceiling, so override this only together with appleSiliconTunables.wiredLimitMb. Null = upstream default (0.90). Override DOWN for a host that needs interactive desktop headroom.";
    };

    # bufferCacheLimitGb — per-worker cap on MLX's RETAINED free-buffer cache
    # (MLX_BUFFER_CACHE_LIMIT env var; vllm-mlx 0.4.0 feeds it to
    # mx.set_cache_limit at engine start). Unset, vllm-mlx uses a device-scaled
    # default of max_recommended * gpuMemoryUtilization (~77 GB per worker on a
    # 128 GB host). Bytes are not the problem — buffer COUNT is: every retained
    # free buffer stays in the process ResidencySet and counts against Metal's
    # ~499000 buffer-count ceiling ("[metal::malloc] Resource limit (499000)
    # exceeded" at ~31 GB active with ~90 GB free, 2026-07-09). Multi-resident
    # hosts multiply the retention. Capping the cache forces MLX to actually
    # free buffers back to Metal, trading a little re-allocation latency for
    # immunity headroom. 12 GB comfortably covers a resident brain's steady
    # working-set churn (weights are NOT part of this cache).
    bufferCacheLimitGb = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 12;
      description = "Per-worker MLX retained-buffer-cache cap in GB (MLX_BUFFER_CACHE_LIMIT). Null = vllm-mlx device-scaled default (~gpuMemoryUtilization of device memory), which hoards enough buffers on multi-resident hosts to trip Metal's buffer-count ceiling under concurrency.";
    };

    # enablePrefixCaching — Enable prefix sharing across requests (--enable-prefix-cache).
    # Eliminates re-prefill of unchanged conversation context — the single
    # biggest speed win for multi-turn tool-calling workloads.
    # Pairs with pagedKvCache.
    enablePrefixCaching = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable prefix sharing across requests (--enable-prefix-cache).";
    };

    # pagedKvCache — Use paged KV cache (--use-paged-cache).
    # Required for prefix sharing (enablePrefixCaching).
    pagedKvCache = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use paged KV cache (--use-paged-cache). Required for prefix sharing.";
    };

    # pagedCacheBlockSize — tokens per paged-KV block (--paged-cache-block-size).
    # The engine default (64) shatters long-session KV into enough per-block
    # Metal buffers to trip MLX's buffer-COUNT ceiling ("[metal::malloc]
    # Resource limit (499000) exceeded" — not a byte OOM). 256 validated with a
    # 113K-token request 2026-07-09 (nix-darwin#1609). Null = engine default.
    # Only meaningful with pagedKvCache; leave null for hybrid-attention
    # families (qwen3_next) where larger blocks are unvalidated.
    pagedCacheBlockSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Tokens per paged-KV-cache block (--paged-cache-block-size). Null = engine default (64). Larger blocks reduce Metal buffer count on long contexts.";
    };

    # prefillBatchSize — Batch size for prompt prefill processing (--prefill-batch-size).
    # Default: null = server picks optimal value based on available memory.
    # Previously --prefill-step-size; renamed in v0.2.6.
    # Larger values can improve TTFT on long prompts but increase memory pressure.
    # Revisit: benchmark specific values if TTFT is a concern.
    prefillBatchSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Prefill batch size (tokens). Null = server default. Larger = faster TTFT, more memory.";
    };
  };
}
