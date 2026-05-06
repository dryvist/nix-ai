#
# MLX Module — KV cache and prefill options
#
# vllm-mlx 0.2.9 PERFORMANCE TUNING.
# Benchmarked 2026-03-19 on M4 Max 128GB with Qwen3.5-122B-A10B-4bit (~65 GB).
# Memory budgets reference the 122B MoE model (10B active params, ~20 GB).
# Baseline: 55-74 tok/s generation, no parallel request benefit (bandwidth-bound).
#
# vllm-mlx 0.2.9 adds Paged KV Cache + prefix sharing on top of the
# memory-aware cache that auto-sizes based on available RAM. Combined with
# iogpu.wired_limit_mb=118000 (set by nix-darwin's apple-silicon-tunables
# module) this lets us push the cache budget higher without thrashing.
#
{ lib, ... }:
{
  options.programs.mlx = {
    # cacheMemoryMb — Override the memory-aware cache size (--cache-memory-mb).
    # Default: 32768 (32GB). Larger cache amortises prefix-cache reuse on
    # multi-turn agentic workloads. With a 65GB model + 32GB cache the
    # footprint sits at ~97GB, fitting within the 118GB wired ceiling set by
    # nix-darwin's apple-silicon-tunables module. Lower to 16384 if reverting.
    # Set to null to restore server auto-detect (~20% RAM = ~25.6GB).
    # Ref: https://github.com/ml-explore/mlx-lm/issues/883
    cacheMemoryMb = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 32768;
      description = "Cache memory limit in MB. Null = auto-detect. Default 32GB amortises prefix-cache reuse on multi-turn workloads.";
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
