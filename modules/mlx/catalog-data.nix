# Validated MLX model catalog — pure data (model entries), shipped with the
# module. The entry schema and the shared serve-arg helpers inherited below
# (parser stacks, timeout, paged-block sizes, swap tier) are documented in
# catalog-lib.nix; this file is split out to keep each under the 12KB gate.
let
  inherit (import ./catalog-lib.nix)
    qwenMoeGeneralParser
    qwenMoeInstructParser
    agentTimeout
    block256
    block512
    hybridNoPaged
    swapFlags
    ;
in
{
  # Small resident auxiliary model for bounded classification and judging.
  # OptiQ keeps tool/reasoning compatibility with the Qwen family while the
  # 4-bit footprint permits it to stay warm beside the primary 80B brain.
  qwen35-9b-optiq = {
    model = "mlx-community/Qwen3.5-9B-OptiQ-4bit";
    weightGb = 7.7;
    # The model card's Hermes recipe serves this text quant with mlx_lm.server.
    # Keep it off the multimodal-aware vllm-mlx loader.
    server = "mlx-lm";
    args = [
      "--max-tokens"
      "512"
      "--chat-template-args"
      (builtins.toJSON {
        enable_thinking = false;
      })
      "--decode-concurrency"
      "1"
      "--prompt-concurrency"
      "1"
    ];
    concurrencyLimit = 1;
    classes = {
      resident.flags = { };
      swap.flags = swapFlags;
    };
  };

  # Agentic tool-calling brain (2026-07-08 bench winner; verdicts in
  # HF JacobPEvans/mlx-benchmarks). Thinking ON is part of the verdict.
  qwen36-optiq = {
    model = "mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit";
    weightGb = 19.5;
    args =
      qwenMoeGeneralParser
      ++ [
        "--default-chat-template-kwargs"
        (builtins.toJSON {
          enable_thinking = true;
        })
      ]
      ++ agentTimeout;
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
    args = [
      "--tool-call-parser"
      "qwen3_coder"
    ]
    ++ agentTimeout;
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
      "--tool-call-parser"
      "qwen3_coder"
      "--reasoning-parser"
      "qwen3"
      "--default-chat-template-kwargs"
      (builtins.toJSON {
        enable_thinking = false;
      })
    ]
    ++ agentTimeout;
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
    args = qwenMoeGeneralParser ++ agentTimeout;
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

  # Instruct sibling of the Thinking brain above — the 2026-07-17 agentic-bench
  # winner and new fleet brain (perfect 1.0 valid_tool_call_rate across every
  # single-stream cell, thinking on/off x ctx small/large x stream/nostream;
  # envelopes in HF JacobPEvans/mlx-benchmarks). Same qwen3_next
  # hybrid-attention constraint as the Thinking entry: paged cache off
  # (hybridNoPaged) because paged-block reconstruction fails every multi-turn
  # request; the standard KV cache runs instead. Resident profile mirrors the OptiQ brain it
  # replaces — 65536 serving window (Hermes' >=64K floor; also serves as the
  # compression model), 16 GB KV. SINGLE-SLOT (40B+ policy, below): maxNumSeqs=1
  # at the engine AND concurrencyLimit=1 at the proxy — this family's ceiling
  # crashes hit under any concurrency, and prefix-cache reconstruction is broken
  # upstream (mlx-lm#1162, INC-17130) so every tool turn full-reprefills 85-100s;
  # batching multiple such requests only time-slices one GPU and balloons every
  # caller's latency into the 429 storm. One request at a time, queue the rest.
  qwen3-next-80b-instruct = {
    model = "mlx-community/Qwen3-Next-80B-A3B-Instruct-4bit";
    weightGb = 42.0;
    # qwen3_next HYBRID: 48 layers, full_attention_interval=4 → only 12
    # full-attention layers carry paged KV; the other 36 gated-delta-net layers
    # carry none (mlx-lm qwen3_next.py:360 is_linear, :450 make_cache). Counting
    # all 48 would over-reserve KV by 4x. kvHeads=2, headDim=256.
    # perTokenKvBytes = 2*12*2*256*2 = 24576 B/token (24 KiB/token) — LOWER than
    # the 30B dense models despite 2.4x the weights, because 3/4 of its layers
    # are KV-free. (Thinking sibling qwen3-next-80b has identical arch.)
    kv = {
      kvLayers = 12;
      kvHeads = 2;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    args = qwenMoeInstructParser ++ agentTimeout;
    # 40B+ SINGLE-SLOT POLICY (user directive 2026-07-21): no concurrency on any
    # 40B+ model. Two layers, defense in depth: concurrencyLimit=1 makes
    # llama-swap QUEUE excess requests (single in-flight to the worker) instead
    # of parallel-dispatch + 429-storm; maxNumSeqs=1 (in flags) caps the engine
    # batch width so even a proxy regression cannot re-enable batching. This 80B
    # aborts with metal::malloc resource-limit errors under concurrent requests
    # (Hermes crons + fleet traffic), and the crash-loop respawn storm exhausts
    # the per-uid process table — reliability over throughput.
    concurrencyLimit = 1;
    classes = {
      resident.flags = hybridNoPaged // {
        cacheMemoryMb = 16384;
        maxNumSeqs = 1;
        maxRequestTokens = 65536;
      };
      swap.flags =
        swapFlags
        // hybridNoPaged
        // {
          cacheMemoryMb = 4096;
          maxNumSeqs = 1; # 40B+ single-slot policy (overrides swapFlags maxNumSeqs=2)
        };
    };
  };

  # gpt-oss MUST set --reasoning-parser gpt_oss — unset, its harmony channel
  # markers leak into streamed message.content (nix-ai#1083). Paged cache +
  # prefix caching OFF: sliding-window attention hits [broadcast_shapes] with
  # vllm-mlx 0.4.0's paged cache.
  gpt-oss-120b = {
    model = "mlx-community/gpt-oss-120b-MXFP4-Q8";
    weightGb = 63.3;
    args = [
      "--tool-call-parser"
      "harmony"
      "--reasoning-parser"
      "gpt_oss"
      # Server defaults keep request-level chat_template_kwargs overrideable.
      "--default-chat-template-kwargs"
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
      };
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
    args = [
      "--tool-call-parser"
      "hermes"
    ];
    classes = {
      swap.flags = swapFlags;
    };
  };
}
