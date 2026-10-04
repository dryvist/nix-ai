# Validated MLX model catalog — pure data (model entries), shipped with the
# module. Holds the models the role map (lib/role-map.nix) references plus the
# cluster-mode model; programs.mlx.roleMap's assertion requires every role-map
# model to be an entry here. Per-model limits come from homelab-contracts;
# backend-specific args and KV geometry stay local. qwen38-27b lives in its own
# file (12KB gate), merged below.
let
  modelCatalog = import ./model-catalog.nix;
  ocr = modelCatalog."mlx-community/Unlimited-OCR-bf16";
  mimo = modelCatalog."mlx-community/MiMo-V2.6-Distill-Qwen-9B-OptiQ-4bit";
  mimoProfile = mimo.profiles.mlx;
  mimoSwap = mimoProfile.swap;
  mimoMaxOutputTokens = mimoProfile.max_output_tokens;
  mimoConcurrency = mimoProfile.max_parallel_requests;
  mimoSwapFlags = {
    autoUnloadIdleSeconds = mimoSwap.auto_unload_idle_seconds;
    maxNumSeqs = mimoSwap.max_num_sequences;
    maxRequestTokens = mimoSwap.max_request_tokens;
  }
  // (
    if mimoSwap ? paged_cache_block_size then
      {
        pagedCacheBlockSize = mimoSwap.paged_cache_block_size;
      }
    else
      { }
  );
in
(import ./catalog-data-qwen38-27b.nix)
// {
  # Keep this entry while the pinned role map still names the vision model.
  # It is outside a host's static resident set unless explicitly selected.
  unlimited-ocr = {
    model = ocr.name;
    backend = "mlx-vlm";
    weightGb = 6.7;
    args = [ ];
    contextWindowTokens = ocr.context_window;
    concurrency = ocr.max_parallel_requests;
    concurrencyLimit = ocr.max_parallel_requests;
    classes = {
      swap.flags = { };
    };
  };

  # The small/fast role model (role map: fast, cheap, small, judge, recorder).
  # A Qwen3.5-9B distill with the qwen3_5_text HYBRID geometry (8
  # full-attention layers carry KV, 32 KiB/token). Served thinking-off.
  # Four-way batching is sized against the measured 40,960-token request
  # window; residency arithmetic in staticmbp-report.md shows the four
  # concurrent KV streams fit below the MacBook wired ceiling.
  mimo-9b = {
    model = "mlx-community/MiMo-V2.6-Distill-Qwen-9B-OptiQ-4bit";
    weightGb = 7.1;
    kv = {
      kvLayers = 8;
      kvHeads = 4;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    contextWindowTokens = mimoProfile.context_window;
    maxOutputTokens = mimoMaxOutputTokens;
    concurrency = mimoConcurrency;
    queueSize = mimoProfile.queue_size;
    prefillTokensPerSecond = mimoProfile.prefill_tokens_per_second;
    decodeTokensPerSecond = mimoProfile.decode_tokens_per_second;
    servicePort = 11433;
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = false;
      })
    ];
    classes = {
      resident = {
        cacheProvisioning.concurrency = mimoConcurrency;
        flags.maxTokens = mimoMaxOutputTokens;
      };
      swap = {
        cacheProvisioning.pinned = {
          mb = mimoSwap.cache_memory_mb;
          reason = "same pinned value as the prior 9B swap entries; unvalidated formula, #1641 buffer-leak history";
          tracking = "vikunja#106";
        };
        flags = mimoSwapFlags;
      };
    };
  };

  # Pipeline-parallel cluster model. Cluster hosts select this catalog key;
  # the physical model id stays centralized here with the standalone models.
  glm47-reap50 = {
    model = "mlx-community/GLM-4.7-REAP-50-mxfp4";
    weightGb = 98.0;
    architecture = "glm4_moe";
    cluster = true;
    args = [ ];
    classes = { };
  };
}
