# Validated MLX model catalog — pure data, shipped with the module.
#
# This is the single source of truth for HOW each known model is served:
# family serve args (parser stack, chat-template kwargs) and per-class
# validated flag profiles. Hosts only pick WHICH entries to enable, the
# class, and a few type-bounded tweaks (programs.mlx.catalog, see
# options-catalog.nix) — detailed serve args never belong in host config.
#
# Entry schema:
#   model            physical Hugging Face id
#   weightGb         4-bit weight footprint (co-residency budget accounting)
#   args             family serve args, applied in every class
#   classes.<class>  validated profile: { flags = modelFlagOverrides attrs }
#     resident — preload-capable agent brain (host preload list still decides
#                what actually warms at boot)
#     swap     — on-demand, idle-unloaded, small caps
# An entry only offers the classes it has been validated for; requesting an
# unoffered class fails the eval.
let
  # Qwen3.6/Next MoE lineage: XML tool format needs hermes (qwen3_coder
  # mis-parses it → empty function.name repair storms) + qwen3 reasoning.
  qwenMoeGeneralParser = [
    "--tool-call-parser"
    "hermes"
    "--reasoning-parser"
    "qwen3"
  ];
  # Guard chain: server 3600 > router 2400 > client 1800 (lifts the
  # 300 s disconnect_guard).
  agentTimeout = [
    "--timeout"
    "3600"
  ];
  # Paged-cache block sizing (engine default 64): long sessions shatter the KV
  # into enough per-block Metal buffers to trip MLX's buffer-count limit
  # ("Resource limit (499000) exceeded", not a byte OOM; nix-darwin#1609).
  # Residents run 512: 256 (validated 113K single-stream) still tripped once
  # under 2x ~50K-token concurrency + a 16K-token generation on 2026-07-09
  # even with the MLX_BUFFER_CACHE_LIMIT cap — 512 halves the per-token block
  # count again (worst case ~98K buffers at maxNumSeqs 8 x 65K window, deep
  # under the ceiling). Swap tier stays 256: its 32K request cap keeps block
  # counts low, and 512 is unvalidated there.
  block256 = {
    pagedCacheBlockSize = 256;
  };
  block512 = {
    pagedCacheBlockSize = 512;
  };
  # Swap tier: on-demand, idle-unloaded, small caps.
  swapFlags = {
    autoUnloadIdleSeconds = 900;
    maxNumSeqs = 2;
    maxRequestTokens = 32768;
  };
in
{
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

  # Stock sibling of the OptiQ brain. Parser anomaly: still qwen3_coder
  # (predates the 2026-07-08 bench); flip to the family parser only with a
  # bench on this variant. Thinking off by default (requests can opt in).
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
    ];
    classes = {
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
  # in mlx-benchmarks docs/RUNBOOK.md). prefixCaching off — unsupported for
  # the qwen3_next hybrid-attention family. block256 on the full-attention
  # layers: the engine-default 64 tripped the Metal buffer-count ceiling
  # mid-digest at step 250880 on 2026-07-10 (active=67GB, running=2) — the
  # hybrid's recurrent layers carry no KV blocks, so the paged block size
  # only shapes its full-attention layers.
  qwen3-next-80b = {
    model = "mlx-community/Qwen3-Next-80B-A3B-Thinking-4bit";
    weightGb = 42.0;
    args = qwenMoeGeneralParser ++ agentTimeout;
    classes = {
      swap.flags =
        block256
        // swapFlags
        // {
          cacheMemoryMb = 4096;
          enablePrefixCaching = false;
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
    classes = {
      # 63 GB — never resident; idle unload frees it back to baseline.
      swap.flags = {
        pagedKvCache = false;
        enablePrefixCaching = false;
        autoUnloadIdleSeconds = 900;
      };
    };
  };

  # Standard-attention MoE workstation default; hermes tool calling
  # (nix-ai#915).
  qwen3-30b-2507 = {
    model = "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit";
    weightGb = 17.5;
    args = [
      "--tool-call-parser"
      "hermes"
    ];
    classes = {
      swap.flags = swapFlags;
    };
  };
}
