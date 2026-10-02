# Validated MLX model catalog — pure data (model entries), shipped with the
# module. Holds the models the role map (lib/role-map.nix) references plus the
# cluster-mode model; programs.mlx.roleMap's assertion requires every role-map
# model to be an entry here. The entry schema and the shared serve-arg helpers
# inherited below are documented in catalog-lib.nix. qwen38-27b lives in its
# own file (12KB gate), merged below.
let
  inherit (import ./catalog-lib.nix) swapFlags;
in
(import ./catalog-data-qwen38-27b.nix)
// {
  # Document OCR, on demand. The only non-text entry in the catalog: an
  # SAM + CLIP-L + DeepSeek-V2 vision-language model, so it CANNOT run on the
  # host's mlx_lm.server (no image input path) and pins backend = "mlx-vlm".
  # mlx-vlm carries this architecture explicitly — its prompt_utils MODEL_CONFIG
  # registry maps model_type "unlimited-ocr" to a single-image message format.
  #
  # WEIGHTS MUST BE PRE-CACHED (worker-env.nix sets HF_HUB_OFFLINE=1) — run
  # `hf download mlx-community/Unlimited-OCR-bf16` on the serving host before
  # enabling this. HF_HUB_OFFLINE=1 makes an uncached id 502 for minutes rather
  # than fetch. Note the near-miss names already on disk there
  # (LoJexLLM/Unlimited-OCR-MLX, baidu/Unlimited-OCR) are DIFFERENT repos and
  # do not satisfy this id.
  #
  # swap only, never resident: OCR is bursty and 6.7 GB of bf16 weights should
  # not sit in the co-residency budget between documents. No swapFlags — those
  # are mlx_lm serve flags (maxNumSeqs/maxRequestTokens/autoUnloadIdleSeconds)
  # that the mlx-vlm adapter rejects; idle unload comes from llama-swap's
  # proxy-side ttl instead, which the host sets via catalog tweaks.ttl.
  #
  # concurrencyLimit 1: a full-page VLM decode is a long single-stream job, and
  # the proxy admitting parallel requests to a one-at-a-time worker is what
  # produced the 429s that motivated effectiveConcurrency in the first place.
  unlimited-ocr = {
    model = "mlx-community/Unlimited-OCR-bf16";
    backend = "mlx-vlm";
    weightGb = 6.7;
    args = [ ];
    concurrencyLimit = 1;
    classes = {
      swap.flags = { };
    };
  };

  # The small/fast role model (role map: fast, cheap, small, judge, recorder).
  # A Qwen3.5-9B distill with the qwen3_5_text HYBRID geometry (8
  # full-attention layers carry KV, 32 KiB/token). Served thinking-off.
  # concurrencyLimit 2 is the role map's concurrency for this model; #1641
  # (OptiQ batched-decode leak on this family) caps it there.
  mimo-9b = {
    model = "mlx-community/MiMo-V2.6-Distill-Qwen-9B-OptiQ-4bit";
    weightGb = 7.1;
    kv = {
      kvLayers = 8;
      kvHeads = 4;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = false;
      })
    ];
    concurrencyLimit = 2;
    classes = {
      resident.cacheProvisioning.concurrency = 2;
      swap = {
        cacheProvisioning.pinned = {
          mb = 8192;
          reason = "same pinned value as the prior 9B swap entries; unvalidated formula, #1641 buffer-leak history";
          tracking = "vikunja#106";
        };
        flags = swapFlags;
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
