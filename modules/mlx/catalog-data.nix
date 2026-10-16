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
  qwen35 = modelCatalog."mlx-community/Qwen3.5-9B-OptiQ-4bit";
  qwen35Profile = qwen35.profiles.mlx;
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

  # The workstation small/fast resident (fast, cheap, small, judge, recorder).
  qwen35-9b = {
    model = qwen35.name;
    # Conservative bound from the 8.22 GB repository total (shards total about 7.1 GB).
    weightGb = 8.3;
    kv = {
      kvLayers = 8;
      kvHeads = 4;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    contextWindowTokens = qwen35Profile.context_window;
    maxOutputTokens = qwen35Profile.max_output_tokens;
    concurrency = qwen35Profile.max_parallel_requests;
    queueSize = qwen35Profile.queue_size;
    concurrencyLimit = qwen35Profile.max_parallel_requests + qwen35Profile.queue_size;
    prefillTokensPerSecond = qwen35Profile.prefill_tokens_per_second;
    decodeTokensPerSecond = qwen35Profile.decode_tokens_per_second;
    servicePort = 11409;
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = true;
      })
    ];
    classes.resident = {
      cacheProvisioning.concurrency = qwen35Profile.max_parallel_requests;
      flags.maxTokens = qwen35Profile.max_output_tokens;
    };
  };

  # The server-class small/fast role model (role map: fast, cheap, small, judge, recorder).
  # A Qwen3.5-9B distill with the qwen3_5_text HYBRID geometry (8
  # full-attention layers carry KV, 32 KiB/token). Served thinking-on.
  # Four-way batching follows the model profile's 40,960-token request window.
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
    # Admission: worker concurrency plus the bounded queue.
    concurrencyLimit = mimoConcurrency + mimoProfile.queue_size;
    prefillTokensPerSecond = mimoProfile.prefill_tokens_per_second;
    decodeTokensPerSecond = mimoProfile.decode_tokens_per_second;
    servicePort = 11409;
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = true;
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
