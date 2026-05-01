#
# MLX Module — Option Declarations
#
# All `options.programs.mlx` declarations live here.
# Active options are defined normally; inactive options are commented out
# with rationale for why they're disabled and when to revisit.
#
{ config, lib, ... }:
{
  options.programs.mlx = {
    enable = lib.mkEnableOption "MLX inference server via vllm-mlx";

    defaultModel = lib.mkOption {
      type = lib.types.str;
      inherit (config.services.aiStack.models) default;
      defaultText = lib.literalExpression "config.services.aiStack.models.default";
      description = ''
        Physical mlx-community/ HuggingFace model ID for the "default" role.
        Sourced from services.aiStack.models.default — see
        nix-ai/modules/ai-stack/default.nix for the registry.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port for the vllm-mlx API server (avoids conflict with 8080 used by Open WebUI)";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address for the vllm-mlx API server";
    };

    huggingFaceHome = lib.mkOption {
      type = lib.types.str;
      default = "/Volumes/HuggingFace";
      description = "Path to HuggingFace model cache (dedicated APFS volume)";
    };

    # ---- vllm-mlx 0.2.9 PERFORMANCE TUNING ----
    # Benchmarked 2026-03-19 on M4 Max 128GB with Qwen3.5-122B-A10B-4bit (~65 GB).
    # Memory budgets below reference the 122B MoE model (10B active params, ~20 GB).
    # Baseline: 55-74 tok/s generation, no parallel request benefit (bandwidth-bound).
    #
    # vllm-mlx 0.2.9 adds Paged KV Cache + prefix sharing on top of the
    # memory-aware cache that auto-sizes based on available RAM. Combined with
    # iogpu.wired_limit_mb=118000 (set by nix-darwin's apple-silicon-tunables
    # module) this lets us push the cache budget higher without thrashing.

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

    # ---- CONCURRENCY & BATCHING OPTIONS (vllm-mlx 0.2.9) ----
    # Complete parameter reference from `vllm-mlx serve --help`.
    # 0.2.9 fixed the 0.2.8 MLLM detection bug for Qwen3-class models, so
    # continuous batching + maxNumSeqs are now defaults rather than opt-in.

    # continuousBatching — Enable continuous batching (--continuous-batching).
    # Improves multi-user throughput by interleaving prefill and decode across
    # requests. The 0.2.8 MLLM-detection bug for Qwen3-class models is fixed
    # in 0.2.9, so this is now safe to default on. Pairs with maxNumSeqs to
    # bound concurrent memory pressure.
    continuousBatching = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable continuous batching. Better throughput across concurrent requests.";
    };

    # maxNumSeqs — Max concurrent sequences (--max-num-seqs).
    # Default: 4 — bounds memory pressure when continuousBatching is on. With
    # 32GB cache + prefix sharing, 4 concurrent sequences fit comfortably even
    # on the 122B MoE model.
    maxNumSeqs = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 4;
      description = "Max concurrent sequences. Default 4 bounds memory pressure with continuousBatching.";
    };

    # chunkedPrefillTokens — Max prefill tokens per scheduler step (--chunked-prefill-tokens).
    # Server default: 0 (disabled). Prevents prefill starvation in multi-request
    # scenarios by limiting how many tokens are prefilled before yielding to decode.
    # Option default: null (disabled). Set to 256-2048 when enabling continuousBatching.
    chunkedPrefillTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = "Max prefill tokens per scheduler step. 0 = disabled. Prevents prefill starvation.";
    };

    # completionBatchSize — Completion batch size (--completion-batch-size).
    # Server default: unset. Controls decode batching — how many tokens are
    # generated per decode step across concurrent sequences.
    # Default: null (server default). Tune alongside maxNumSeqs.
    completionBatchSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Completion batch size. Null = server default. Tune with continuousBatching.";
    };

    # maxTokens — Default max generation length (--max-tokens).
    # Server default: 32768. Only affects requests that omit max_tokens.
    # Some OpenAI-compatible consumers omit max_tokens even when their model
    # metadata has a token cap. Keep this nullable so explicit client limits
    # still win, but allow the server default to be capped for local
    # multi-request workloads.
    maxTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Default max tokens when client omits max_tokens. Null = vllm-mlx server default: 32768.";
    };

    # ---- TOOL INTEGRATION ----
    # Server-side tool calling returns structured tool_calls in OpenAI API responses.
    # Without these flags, streaming tool calls are broken (raw XML leaks as text)
    # and non-streaming relies on a fragile generic parser.

    # enableAutoToolChoice — Activate model-specific tool call parsing (--enable-auto-tool-choice).
    # No-op when request has no `tools` parameter, so safe to leave on.
    # Default: true — primary use case is tool calling via PAL MCP.
    enableAutoToolChoice = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic tool choice for supported models. No-op when request has no tools.";
    };

    # toolCallParser — Tool call parser (--tool-call-parser).
    # Default: "hermes" — handles Nemotron XML format (<tool_call><function=...>)
    # that Qwen3.5 produces, and supports native tool format for multi-turn
    # conversations. Override to "auto", "qwen3_coder", etc. if needed.
    toolCallParser = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "auto"
          "mistral"
          "qwen"
          "qwen3_coder"
          "llama"
          "hermes"
          "deepseek"
          "kimi"
          "granite"
          "nemotron"
          "xlam"
          "functionary"
          "glm47"
        ]
      );
      default = "hermes";
      description = "Tool call parser. Only used with enableAutoToolChoice. 'hermes' handles Nemotron XML (<tool_call><function=...>) and supports native tool format for multi-turn conversations.";
    };

    # reasoningParser — Reasoning content extraction (--reasoning-parser).
    # Extracts <think>...</think> into structured reasoning_content field.
    # DISABLED PENDING VERIFICATION: vllm-mlx 0.2.6 had a bug where
    # --reasoning-parser and --tool-call-parser were mutually exclusive in
    # streaming mode (server.py bypassed the tool parser when reasoning parser
    # was active). 0.2.9 may have fixed this — re-enable cautiously after
    # verifying that streaming tool_calls still work for Qwen3-class models.
    # Without this flag, <think> blocks still appear in content text — most
    # consumers parse them from text as a fallback.
    reasoningParser = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "qwen3"
          "deepseek_r1"
          "harmony"
        ]
      );
      default = null;
      description = "Reasoning content extraction parser. Disabled by default — conflicts with tool-call-parser in streaming mode (vllm-mlx bug).";
    };

    # ---- OOM PREVENTION (2026-03-21 incident: 171.9 GB on 128 GB RAM) ----
    # ProcessType=Background makes vllm-mlx Jetsam-eligible; HardResourceLimits
    # sets a kernel-enforced RSS ceiling. KeepAlive auto-restarts after Jetsam kill.

    memoryHardLimitGb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Hard RSS limit in GB. Kernel kills process above this. Leaves 28GB for OS + apps on 128GB systems.";
    };

    # ---- MODEL SWITCHING (llama-swap proxy) ----
    # llama-swap sits on the API port and manages vllm-mlx backends as child processes.
    # Model switching is transparent: send a request with model: "X" and the proxy handles it.

    models = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional vllm-mlx serve arguments for this model";
            };
            ttl = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 0;
              description = "Seconds of idle time before unloading. 0 = use proxy.idleTtl default.";
            };
            aliases = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Alternative model names that route to this model";
            };
          };
        }
      );
      default = { };
      description = "Additional models available for on-demand switching via llama-swap proxy. The defaultModel is always available with TTL 0.";
    };

    proxy = {
      healthCheckTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 180;
        description = "Seconds to wait for a backend to become healthy. 70GB models take 20-60s to load; 180s covers the worst case.";
      };
      idleTtl = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 1800;
        description = "Default idle TTL in seconds for non-default models. 0 = never auto-unload. Default 30 min.";
      };
      logLevel = lib.mkOption {
        type = lib.types.enum [
          "debug"
          "info"
          "warn"
          "error"
        ];
        default = "info";
        description = ''
          llama-swap log verbosity. "info" is the production default — keeps
          model load events and swap transitions visible without dumping every
          weight tensor name. Switch to "debug" only when actively diagnosing
          proxy behaviour (logs every proxied HTTP request/response body and
          makes `curl http://127.0.0.1:11434/logs/stream` a live I/O tap).
          Note: debug output rotates within the 10 MB LaunchAgent log limit.
        '';
      };
      logToStdout = lib.mkOption {
        type = lib.types.enum [
          "proxy"
          "upstream"
          "both"
          "none"
        ];
        default = "both";
        description = ''
          Which output streams llama-swap forwards to stdout (and therefore
          the /logs/stream SSE endpoint). "both" interleaves proxy request
          logs with vllm-mlx upstream output. "proxy" (default upstream
          behaviour) shows only proxy-level events.
        '';
      };
    };
  };
}
