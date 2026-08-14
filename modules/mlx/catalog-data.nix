# Validated MLX model catalog — pure data (model entries), shipped with the
# module. The entry schema and the shared serve-arg helpers inherited below
# (parser stacks, timeout, paged-block sizes, swap tier) are documented in
# catalog-lib.nix; this file is split out to keep each under the 12KB gate.
# See catalog-lib.nix for the #1334 KV-quant/MTP flag-availability note.
# qwen3-next-80b-instruct lives in catalog-data-80b-instruct.nix, merged
# below, for the same size-gate reason.
let
  inherit (import ./catalog-lib.nix)
    block256
    block512
    hybridNoPaged
    swapFlags
    ;
in
(import ./catalog-data-80b-instruct.nix)
// {
  # Small resident auxiliary model for bounded classification and judging.
  # OptiQ keeps tool/reasoning compatibility with the Qwen family while the
  # 4-bit footprint permits it to stay warm beside the primary 80B brain.
  # #1641: batched decode leaks Metal buffers on this family — swapFlags'
  # maxNumSeqs=2 keeps it narrow; do not raise it.
  qwen35-9b-optiq = {
    model = "mlx-community/Qwen3.5-9B-OptiQ-4bit";
    weightGb = 7.7;
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
      resident.flags = { };
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
  # 502s after minutes of retrying rather than failing fast. Observed on
  # jevans-ms 2026-08-05: this exact id was registered and requested while only
  # the OptiQ-4bit variant was on disk, so every call to it 502'd for weeks with
  # nothing reporting why. Registration makes an id SERVABLE, never CACHED.
  # `hf download <id>` (or the prefetch agent) is the step that caches it.
  # #1641 (same family as qwen35-9b-optiq): maxNumSeqs low, see its comment.
  qwen35-9b-mlx = {
    model = "mlx-community/Qwen3.5-9B-MLX-4bit";
    weightGb = 5.2;
    # Text quant served through mlx_lm.server; keep off the vllm-mlx loader.
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = false;
      })
    ];
    concurrencyLimit = 1;
    classes = {
      resident.flags = { };
      swap.flags = swapFlags;
    };
  };

  # Resident Hermes goal judge and default small/midsize model.
  #
  # Drop-in successor to qwen36-27b-mxfp4: both are model_type qwen3_5_text with
  # an IDENTICAL attention topology — 64 layers split 16 full_attention /
  # 48 linear_attention, num_key_value_heads 4, head_dim 256 (read from each
  # model's own config.json on jevans-ms, 2026-08-14). Same geometry means the
  # incumbent's validated serve flags transfer verbatim; nothing here is guessed.
  #
  # Note this family is HYBRID attention but is NOT qwen3_next: it does not hit
  # the mlx-lm#1162 paged-block reconstruction failure, which is why the
  # incumbent runs without hybridNoPaged and this entry does the same. Do not
  # "fix" that by adding hybridNoPaged on the strength of the layer_types field
  # alone — the incumbent has served this topology in production for weeks.
  #
  # Thinking is ON but BOUNDED. This model's reasoning is the reason it was
  # adopted, so serving it thinking-off gives up what it was chosen for — but
  # its chat template defaults reasoning_effort to 'xhigh' when the kwarg is
  # unset, and at xhigh it does not finish. Measured on an isolated worker
  # (jevans-ms, 2026-08-14, 3 runs, max_tokens 4096): 0 answer characters,
  # 16399 reasoning characters, finish_reason "length" every run. Pinning
  # 'low' is what makes it answer: 3/3 runs finish_reason "stop", 10079 answer
  # against 5051 reasoning characters, 3842 completion tokens.
  #
  # The template accepts only xhigh | medium | low. 'medium' was measured too,
  # and it also completes at this worker's 8192-token budget: 4243 tokens,
  # 13456 answer against 2334 reasoning characters, finish_reason "stop". It
  # reasons LESS than low and answers more, which is not a contradiction —
  # medium injects NO instruction at all (the prompt is 89 tokens against low's
  # 119, the difference being low's "keep your thinking brief" string), so it
  # is the model's unsteered baseline rather than a step up a dial.
  #
  # low is kept anyway, and the reason is bounding, not quality: low carries an
  # explicit brevity instruction, so its thinking is bounded by construction,
  # while medium is unbounded by instruction and differs from xhigh only in
  # degree. On one 89-token prompt medium is fine; on a hard agentic prompt
  # nothing stops it running long, and mlx-lm has no mechanism to cap it —
  # reasoning_effort is a prompt string, not a budget. Revisit when vllm-mlx's
  # thinking_token_budget can enforce a real ceiling.
  qwen38-27b = {
    model = "mlx-community/Qwen3.8-27B-4bit";
    weightGb = 16.1;
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        reasoning_effort = "low";
      })
    ];
    # NO concurrencyLimit. The entry this replaced carried concurrencyLimit = 1
    # because it was a latency-sensitive judge that never needed concurrent
    # decode. This entry is the fleet brain every role resolves to, so pinning
    # it to 1 would make llama-swap serialize every request on the host.
    classes = {
      # Fleet-brain resident profile, matched to the entry it takes over from:
      # HIGH caps for 40-58K agentic contexts. maxRequestTokens 65536 is load
      # bearing — 32768 fed a truncation/retry death-loop.
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
      # The global maxRequestTokens default is too low for agentic multi-turn.
      resident.flags = block512 // {
        maxRequestTokens = 32768;
      };
      swap.flags = block256 // swapFlags;
    };
  };

  # Stock sibling of the OptiQ brain, and the live ai-default fleet brain
  # (nix-ai#915). Parser anomaly: still qwen3_coder (predates the 2026-07-08
  # bench); flip to the family parser only with a bench on this variant.
  # Thinking off by default (requests can opt in). agentTimeout is REQUIRED
  # here now that it fronts the fleet: without it the serve worker keeps the
  # 300 s disconnect_guard, which aborted long cron generations mid-stream
  # ("ABORTING orphaned request … in 300.4s") and surfaced to Hermes as a
  # brain-unreachable event on 2026-07-14.
  qwen36-35b = {
    model = "mlx-community/Qwen3.6-35B-A3B-4bit";
    weightGb = 19.4;
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
    args = [ ];
    # 40B+ single-slot policy: proxy queues (single in-flight), engine batch
    # capped at 1 (in swap.flags). Same hybrid-attention re-prefill constraint
    # as the Instruct sibling.
    concurrencyLimit = 1;
    classes = {
      swap.flags =
        swapFlags
        // hybridNoPaged
        // {
          cacheMemoryMb = 4096;
          maxNumSeqs = 1; # 40B+ single-slot policy (overrides swapFlags maxNumSeqs=2)
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
    # qwen3_moe, standard attention: all 48 layers bear KV. jevans-mbp standalone
    # default. perTokenKvBytes = 2*48*4*128*2 = 98304 B/token (96 KiB/token).
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
