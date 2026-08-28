# qwen35-9b-optiq + qwen35-9b-mlx — split out of catalog-data.nix for the
# per-file 12KB gate (same split-rather-than-exempt pattern as
# catalog-data-80b-instruct.nix and catalog-data-qwen38-27b.nix: split the
# entry, never trim the evidence). Merged into the same catalog attrset by
# catalog-data.nix; see that file for the entry schema and catalog-lib.nix
# for the shared serve-arg helpers.
let
  inherit (import ./catalog-lib.nix) swapFlags;
in
{
  # Small resident auxiliary model for bounded classification and judging.
  # OptiQ keeps tool/reasoning compatibility with the Qwen family while the
  # 4-bit footprint permits it to stay warm beside the primary 80B brain.
  # #1641: batched decode leaks Metal buffers on this family — swapFlags'
  # maxNumSeqs=2 keeps it narrow; do not raise it.
  qwen35-9b-optiq = {
    model = "mlx-community/Qwen3.5-9B-OptiQ-4bit";
    weightGb = 7.7;
    # qwen3_5_text HYBRID, same family as qwen38-27b: 32 layers,
    # full_attention_interval 4 -> 8 full-attention layers carry paged KV, the
    # other 24 linear-attention layers carry none.
    # perTokenKvBytes = 2*8*4*256*2 = 32768 B/token (32 KiB/token). Verified
    # against the model's own config.json (2026-08-27).
    kv = {
      kvLayers = 8;
      kvHeads = 4;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    # The model card's Hermes recipe serves this text quant with mlx_lm.server.
    # Keep it off the multimodal-aware vllm-mlx loader.
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = false;
      })
    ];
    concurrencyLimit = 1;
    classes = {
      # No host currently selects this class for this entry (grepped
      # nix-darwin: absent entirely for qwen35-9b-optiq, swap-only for
      # qwen35-9b-mlx) — offered so a future host CAN run either resident,
      # but dead today. Wiring cacheMemoryMb here changes no live behavior,
      # so it is safe to derive rather than leave silently defaulted:
      # concurrency=1 matches the entry's own concurrencyLimit=1 above
      # (#1641 caution — do not raise either without re-testing).
      resident.cacheProvisioning.concurrency = 1;
      swap.flags = swapFlags;
    };
  };

  # Small on-demand summarizer. An hourly note-capture pipe requests
  # this exact physical id ("mlx-community/Qwen3.5-9B-MLX-4bit"); registering it
  # swap-class (no roles -> compiles to a llama-swap models.<id> entry keyed by
  # the physical id) lets that request route without evicting a resident.
  #
  # WEIGHTS MUST BE PRE-CACHED under HF_HOME. This comment used to promise they
  # "fetch from HuggingFace on first load if not already cached" — a promise the
  # runtime forbids: modules/mlx/worker-env.nix sets HF_HUB_OFFLINE=1, so a
  # first load of an uncached id raises OfflineModeIsEnabled and the request
  # 502s after minutes of retrying rather than failing fast. Registering an id
  # here while a different quant variant is the only one cached on disk means
  # every call to it 502s with nothing reporting why. Registration makes an id
  # SERVABLE, never CACHED.
  # `hf download <id>` (or the prefetch agent) is the step that caches it.
  # #1641 (same family as qwen35-9b-optiq): maxNumSeqs low, see its comment.
  qwen35-9b-mlx = {
    model = "mlx-community/Qwen3.5-9B-MLX-4bit";
    weightGb = 5.2;
    # Same qwen3_5_text HYBRID geometry as qwen35-9b-optiq above: 32 layers,
    # 8 full-attention (full_attention_interval 4) carry paged KV.
    # perTokenKvBytes = 2*8*4*256*2 = 32768 B/token (32 KiB/token). Verified
    # against the model's own config.json (2026-08-27).
    kv = {
      kvLayers = 8;
      kvHeads = 4;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    # Text quant served through mlx_lm.server; keep off the vllm-mlx loader.
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = false;
      })
    ];
    concurrencyLimit = 1;
    classes = {
      # No host currently selects this class for this entry (grepped
      # nix-darwin: absent entirely for qwen35-9b-optiq, swap-only for
      # qwen35-9b-mlx) — offered so a future host CAN run either resident,
      # but dead today. Wiring cacheMemoryMb here changes no live behavior,
      # so it is safe to derive rather than leave silently defaulted:
      # concurrency=1 matches the entry's own concurrencyLimit=1 above
      # (#1641 caution — do not raise either without re-testing).
      resident.cacheProvisioning.concurrency = 1;
      swap.flags = swapFlags;
    };
  };
}
