# gpt-oss-120b (MXFP4-Q8) advisor resident. Split out of catalog-data.nix like
# catalog-data-qwen38-27b.nix; merged into the same catalog attrset. Serving
# limits come from homelab-contracts; sizes and attention geometry are read from
# the model's own files on the workstation's HuggingFace cache.
let
  model = (import ./model-catalog.nix)."mlx-community/gpt-oss-120b-MXFP4-Q8";
  profile = model.profiles.mlx;
  contextWindowTokens = profile.context_window;
  maxOutputTokens = profile.max_output_tokens;
  # TODO: no gpt-oss concurrency is recorded in the catalog. 1 matches the
  # Qwen3.8-27B resident (max_parallel_requests 1), the large tier's decode
  # concurrency.
  concurrency = 1;
in
{
  gpt-oss-120b = {
    model = model.name;
    # 63,386,948,506 bytes across 13 safetensors shards: 59.03 GiB, rounded up.
    weightGb = 59.1;
    # config.json: 8 KV heads, head_dim 64, 18 full_attention layers of 36.
    # TODO: sliding_attention layers (window 128) are not counted here, and
    # config.json does not record the KV dtype (2 bytes assumed, as for the
    # 27B). Confirm both against mlx-lm before trusting the cache budget.
    kv = {
      kvLayers = 18;
      kvHeads = 8;
      headDim = 64;
      kvDtypeBytes = 2;
    };
    inherit contextWindowTokens maxOutputTokens concurrency;
    queueSize = profile.queue_size;
    # Admit the active request and the bounded worker queue, as the 27B does.
    concurrencyLimit = profile.queue_size + 1;
    prefillTokensPerSecond = profile.prefill_tokens_per_second;
    decodeTokensPerSecond = profile.decode_tokens_per_second;
    # 11433 is not used by another catalog entry. The 11434 port is a TLS proxy.
    servicePort = 11433;
    args = [ ];
    classes.resident = {
      cacheProvisioning.concurrency = concurrency;
      flags = {
        pagedCacheBlockSize = profile.paged_cache_block_size;
        maxNumSeqs = profile.max_num_sequences;
        maxRequestTokens = contextWindowTokens;
        maxTokens = maxOutputTokens;
      };
    };
  };
}
