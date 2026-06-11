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

    # gpuMemoryUtilization — Per-worker Metal allocation ceiling (--gpu-memory-utilization).
    # Fraction of device memory each vllm-mlx worker may allocate via Metal; the
    # server also uses it as the emergency cache-clear threshold. The upstream
    # default is 0.90, which on a 128 GB host lets a single worker reach ~115 GB
    # before any native bound engages. 0.50 bounds each worker to half of device
    # memory — comfortably above a healthy worker's working set while keeping the
    # host responsive if a worker's allocator grows under sustained load.
    # This is the per-worker enforcement layer that HardResourceLimits could not
    # provide (see launchd.nix) because it acts inside the worker process itself.
    # Ref: https://github.com/ml-explore/mlx-lm/issues/883
    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.nullOr (lib.types.numbers.between 0.05 1.0);
      default = 0.5;
      description = "Fraction of device memory each worker may allocate via Metal (vllm-mlx --gpu-memory-utilization). Null = upstream default (0.90). Also the worker's emergency cache-clear threshold.";
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
