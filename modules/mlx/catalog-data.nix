# Validated MLX model catalog — pure data (model entries), shipped with the
# module. The entry schema and the shared serve-arg helpers inherited below
# (parser stacks, timeout, paged-block sizes, swap tier) are documented in
# catalog-lib.nix; this file is split out to keep each under the 12KB gate.
# See catalog-lib.nix for the #1334 KV-quant/MTP flag-availability note.
# qwen3-next-80b-instruct, qwen38-27b, and the qwen35-9b pair live in their
# own files, merged below, for the same size-gate reason. Each carries long
# measurement notes, which is exactly what pushed this file over the gate —
# split the entry, never trim the evidence.
let
  inherit (import ./catalog-lib.nix)
    block256
    block512
    hybridNoPaged
    swapFlags
    ;
in
(import ./catalog-data-80b-instruct.nix)
// (import ./catalog-data-qwen38-27b.nix)
// (import ./catalog-data-qwen35-9b.nix)
// {
  # Document OCR, on demand. The only non-text entry in the catalog: an
  # SAM + CLIP-L + DeepSeek-V2 vision-language model, so it CANNOT run on the
  # host's mlx_lm.server (no image input path) and pins backend = "mlx-vlm".
  # mlx-vlm carries this architecture explicitly — its prompt_utils MODEL_CONFIG
  # registry maps model_type "unlimited-ocr" to a single-image message format.
  #
  # WEIGHTS MUST BE PRE-CACHED, exactly as for qwen35-9b-mlx above — run
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

  # qwen35-9b-optiq and qwen35-9b-mlx moved to catalog-data-qwen35-9b.nix
  # (12KB gate); merged into this attrset at the top of the file.

  # Agentic tool-calling brain (2026-07-08 bench winner; verdicts in
  # HF JacobPEvans/mlx-benchmarks). Thinking ON is part of the verdict.
  qwen36-optiq = {
    model = "mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit";
    weightGb = 19.5;
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = true;
      })
    ];
    classes = {
      # HIGH KV budget for 40-58K-token contexts; maxNumSeqs 8 = one
      # continuous batch. 65536 replaces the 32768 cap that fed the
      # truncation/retry death-loop.
      resident.flags = block512 // {
        cacheMemoryMb = 16384;
        maxNumSeqs = 8;
        maxRequestTokens = 65536;
      };
      swap.flags =
        block256
        // swapFlags
        // {
          cacheMemoryMb = 3072;
        };
    };
  };

  qwen3-coder-30b = {
    model = "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit";
    weightGb = 17.1;
    # qwen3_moe, standard attention: all 48 layers bear KV.
    # perTokenKvBytes = 2*48*4*128*2 = 98304 B/token (96 KiB/token).
    kv = {
      kvLayers = 48;
      kvHeads = 4;
      headDim = 128;
      kvDtypeBytes = 2;
    };
    args = [ ];
    classes = {
      # cacheMemoryMb PINNED at today's inherited global null-default
      # (derive.nix's cacheMemoryMbFor) — forModel's derivation is
      # unvalidated against a real run. Tracked: Vikunja #106.
      resident = {
        cacheProvisioning.pinned = {
          mb = 8192;
          reason = "matches today's inherited global null-default; forModel's derivation unvalidated against a real run";
          tracking = "vikunja#106";
        };
        # The global maxRequestTokens default is too low for agentic multi-turn.
        flags = block512 // {
          maxRequestTokens = 32768;
        };
      };
      swap.flags = block256 // swapFlags;
    };
  };

  # Stock sibling of the OptiQ brain, and the live ai-default fleet brain
  # (nix-ai#915). Parser anomaly: still qwen3_coder (predates the 2026-07-08
  # bench); flip to the family parser only with a bench on this variant.
  # Thinking off by default (requests can opt in). agentTimeout is REQUIRED
  # here now that it fronts the fleet: without it the serve worker keeps the
  # 300 s disconnect_guard, which aborts long-running generations mid-stream
  # ("ABORTING orphaned request … in 300.4s") and can surface downstream as a
  # brain-unreachable event.
  qwen36-35b = {
    model = "mlx-community/Qwen3.6-35B-A3B-4bit";
    weightGb = 19.4;
    contextWindowTokens = 65536;
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = false;
      })
    ];
    classes = {
      # Fleet-brain resident profile mirrors the OptiQ twin it replaces as
      # ai-default: same weights (~19.4 GB) and same KV budget, so the resident
      # footprint is unchanged. HIGH caps for 40-58K agentic contexts; 65536
      # avoids the 32768 truncation/retry death-loop (see the OptiQ entry).
      resident.flags = block512 // {
        cacheMemoryMb = 16384;
        maxNumSeqs = 8;
        maxRequestTokens = 65536;
      };
      swap.flags =
        block256
        // swapFlags
        // {
          cacheMemoryMb = 3072;
        };
    };
  };

  # LARGE rotation brain. Always-thinking variant (no chat-template switch).
  # Small cache keeps the on-demand swap-in under the memory trip (derivation
  # in mlx-benchmarks docs/RUNBOOK.md). Paged cache off (hybridNoPaged): the
  # qwen3_next hybrid attention fails paged-block reconstruction on every
  # multi-turn request (mlx-lm#1162), wedging the worker; the standard KV cache
  # runs instead. With paged off, the block-size sizing (and its Metal
  # buffer-count ceiling) no longer applies.
  qwen3-next-80b = {
    model = "mlx-community/Qwen3-Next-80B-A3B-Thinking-4bit";
    weightGb = 42.0;
    # qwen3_next HYBRID, identical topology to the Instruct sibling
    # (catalog-data-80b-instruct.nix): 48 layers, full_attention_interval=4,
    # 12 full-attention layers carry paged KV, kvHeads=2, headDim=256.
    # perTokenKvBytes = 2*12*2*256*2 = 24576 B/token. Backfilled for
    # completeness (Vikunja #106); NOT wired to cacheMemoryMb below — see
    # that field's comment.
    kv = {
      kvLayers = 12;
      kvHeads = 2;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    args = [ ];
    # 40B+ single-slot policy: proxy queues (single in-flight), engine batch
    # capped at 1 (in swap.flags). Same hybrid-attention re-prefill constraint
    # as the Instruct sibling.
    concurrencyLimit = 1;
    classes = {
      # cacheMemoryMb PINNED (derive.nix's cacheMemoryMbFor) — same finding
      # as the Instruct sibling's swap class. Tracked: Vikunja #106.
      swap = {
        cacheProvisioning.pinned = {
          mb = 4096;
          reason = "live working value; unvalidated formula, documented crash history under concurrency";
          tracking = "vikunja#106";
        };
        flags =
          swapFlags
          // hybridNoPaged
          // {
            maxNumSeqs = 1; # 40B+ single-slot policy (overrides swapFlags maxNumSeqs=2)
          };
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

  # gpt-oss MUST set --reasoning-parser gpt_oss — unset, its harmony channel
  # markers leak into streamed message.content (nix-ai#1083). Paged cache +
  # prefix caching OFF: sliding-window attention hits [broadcast_shapes] with
  # vllm-mlx 0.4.0's paged cache.
  gpt-oss-120b = {
    model = "mlx-community/gpt-oss-120b-MXFP4-Q8";
    weightGb = 63.3;
    args = [
      # Server defaults keep request-level chat_template_kwargs overrideable.
      "--chat-template-args"
      (builtins.toJSON {
        reasoning_effort = "low";
      })
    ];
    # 40B+ single-slot policy: 63 GB weights on one GPU — proxy queues (single
    # in-flight), engine batch capped at 1 (in swap.flags). Without maxNumSeqs
    # this inherited the global default (4); concurrencyLimit inherited the
    # host-wide 8 — both re-enabled the multi-request storm this policy forbids.
    concurrencyLimit = 1;
    classes = {
      # 63 GB — never resident; idle unload frees it back to baseline.
      swap.flags = {
        pagedKvCache = false;
        enablePrefixCaching = false;
        maxNumSeqs = 1;
        autoUnloadIdleSeconds = 900;
        # The only harmony-family entry in the catalog: pinned rather than
        # left to "auto" so the mode is stated, not re-inferred per turn.
        harmonyToolParser = "on";
      };
    };
  };

  # Gemma 4 QAT OptiQ-4bit, ~23.5 GB. NO reasoningParser: isolation testing
  # found it zeroes non-streaming tool calls together with the tool-call
  # parser (valid_tool_call_rate 0.00 -> 1.00 once removed); leave unset until
  # re-benched alone.
  gemma4-31b-optiq = {
    model = "mlx-community/gemma-4-31B-it-OptiQ-4bit";
    weightGb = 23.5;
    args = [ ];
    concurrencyLimit = 1;
    classes = {
      swap.flags = swapFlags;
    };
  };

  # Standard-attention MoE workstation default; hermes tool calling
  # (nix-ai#915).
  qwen3-30b-2507 = {
    model = "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit";
    weightGb = 17.5;
    # qwen3_moe, standard attention: all 48 layers bear KV. The laptop's
    # standalone default. perTokenKvBytes = 2*48*4*128*2 = 98304 B/token
    # (96 KiB/token).
    kv = {
      kvLayers = 48;
      kvHeads = 4;
      headDim = 128;
      kvDtypeBytes = 2;
    };
    args = [ ];
    classes = {
      swap.flags = swapFlags;
    };
  };
}
