#
# MLX Module — KV cache and prefill options
#
# vllm-mlx 0.2.9 PERFORMANCE TUNING.
# Sizing target: M4 Max 128 GB. Effective wired ceiling 104 GB (from
# nix-darwin's apple-silicon-tunables module via iogpu.wired_limit_mb=104000;
# lowered from 118000 on 2026-06-10 to guarantee 24 GB pageable headroom —
# see nix-mac-performance RC14).
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

    # gpuMemoryUtilization — a DEVICE FRACTION with two coupled effects in
    # vllm-mlx. It is not "share of the host given to inference" (that is the
    # OS wired-memory ceiling, set per host via appleSiliconTunables.wiredLimitMb);
    # it is a fraction of total device memory that:
    #   1. caps how much Metal memory each worker PROCESS may allocate
    #      (allocation_limit = util * device_working_set), and
    #   2. sets the engine's emergency cache-clear TRIP POINT at
    #      device_mem * (util + 0.05) — when total active GPU memory crosses
    #      that, every worker force-clears its KV cache (engine_core.py).
    #
    # Because it is a fraction, ONE value scales correctly across any device
    # size — no per-host math or override is needed, which is why this is a
    # single declared default rather than a per-host knob.
    #
    # Choosing the default: the trip point must sit ABOVE the resident
    # weights+cache a serving host keeps warm, but just BELOW the wired ceiling
    # so the soft cache-clear still fires as a safety valve before hard Metal
    # paging. On a 128 GiB host with a ~92%-wired GPU (~115 GiB), the trip point
    # as a function of util is:
    #   util 0.50 -> ~76 GiB  (below a dual-model ~92 GiB resident set: the
    #                          worker force-clears every step -> KV thrash ->
    #                          multi-turn agent chats die after a few messages)
    #   util 0.80 -> ~109 GiB (clears the ~92 GiB resident set with headroom,
    #                          ~6 GiB under the 115 GiB ceiling: the sweet spot)
    #   util 0.85+ -> >115 GiB (trip lands OVER the wired ceiling; the soft
    #                           valve never fires and you hit hard paging instead)
    # 0.80 also lifts allocation_limit to ~92 GiB/worker, enough to hold a
    # ~63 GiB 120B model plus cache; 0.50 capped it at ~57 GiB, below that
    # model's footprint, so it could not stay resident. A workstation that
    # actively needs interactive desktop headroom can override DOWN.
    # This is the per-worker enforcement layer that HardResourceLimits could not
    # provide (see launchd.nix) because it acts inside the worker process itself.
    # Ref: https://github.com/ml-explore/mlx-lm/issues/883
    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.nullOr (lib.types.numbers.between 0.05 1.0);
      default = 0.8;
      description = "Fraction of device memory each worker may allocate via Metal (vllm-mlx --gpu-memory-utilization), which vllm-mlx also uses as the emergency cache-clear trip point at device_mem*(util+0.05). 0.80 keeps the trip point above a dual-model resident set yet under a ~92%-wired ceiling. Null = upstream default (0.90). Override DOWN only for a host that needs interactive desktop headroom.";
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
