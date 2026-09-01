#
# MLX Module — Concurrency and batching options
#
# Complete parameter reference from `vllm-mlx serve --help`.
#
# These are vllm-mlx flags. continuousBatching therefore DEFAULTS TO WHETHER
# vllm-mlx is the selected backend, not to true -- on a backend whose flag
# builder does not emit --continuous-batching, a `true` here would describe a
# capability the rendered command does not carry. maxNumSeqs still defaults
# unconditionally; it is inert on a builder that does not emit it.
#
{ lib, config, ... }:
{
  options.programs.mlx = {
    # continuousBatching — Enable continuous batching (--continuous-batching).
    # Improves multi-user throughput by interleaving prefill and decode across
    # requests. Pairs with maxNumSeqs to bound concurrent memory pressure.
    #
    # THE DEFAULT IS BACKEND-DERIVED, and that is the point. Only the vllm-mlx
    # flag builder emits --continuous-batching; the mlx-lm builder emits no
    # such flag at all (modules/mlx/model-server-cmd.nix). A flat `default =
    # true` therefore made every mlx-lm host's config read "batching on"
    # against a server that cannot batch, with nothing anywhere surfacing the
    # discrepancy.
    #
    # That is not a cosmetic mismatch. It is how a serial tier gets mistaken
    # for a batched one: on 2026-09-01 the mlx-lm tier was driven at 4-way
    # concurrency and produced 16.8s / 21.1s / 79.1s against a ~12s serial
    # baseline with one request never returning -- queueing and stalling, from
    # a config that claimed continuous batching was enabled.
    #
    # Deriving it means the value is true exactly when it is honoured, so the
    # config states what the server does rather than what was asked for. No
    # behaviour changes for an mlx-lm host: the flag was already ignored there.
    continuousBatching = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.mlx.modelServerBackend == "vllm-mlx";
      defaultText = lib.literalExpression "modelServerBackend == \"vllm-mlx\"";
      description = "Enable continuous batching. Defaults to whether the selected backend can actually honour it.";
    };

    # defaultRepetitionPenalty — server-side default
    # (--default-repetition-penalty).
    #
    # A BATCH-SAFETY control, not a quality knob. In mlx_lm's batch generator,
    # a request carrying no logits processor gets padded with a null entry
    # instead of an empty list, and the decode step iterates that entry
    # blindly. One request bearing a processor, alongside another lacking one,
    # kills the scheduler thread on a type error — every completion on that
    # worker afterwards hangs or comes back empty until the worker is killed.
    #
    # A repetition penalty IS a logits processor. Injecting it per-request at
    # a router mixes penalized traffic with penalty-free callers (health
    # probes, direct clients), and that mix wedges the engine. Setting it here
    # applies it to EVERY request the worker sees, making batches uniform by
    # construction regardless of caller. Uniformity is the property that
    # matters, not the value. Prefer this over router-side injection.
    # See nix-ai#1234.
    defaultRepetitionPenalty = lib.mkOption {
      type = lib.types.nullOr (lib.types.numbers.between 1.0 2.0);
      default = null;
      example = 1.05;
      description = "Server-side default repetition penalty applied to every request (vllm-mlx --default-repetition-penalty). Set this instead of injecting a per-request penalty at the router: a penalty is a logits processor, and mixing processor-ful with processor-free requests in one batch wedges mlx_lm's batch generator (nix-ai#1234). Null = upstream default (no penalty), which is uniform and therefore also safe.";
    };

    # maxNumSeqs — Max concurrent sequences (--max-num-seqs).
    # Default: 4 — bounds memory pressure when continuousBatching is on. The
    # 8 GB (8192 MB) default cache plus prefix sharing holds 4 concurrent
    # sequences comfortably across the small/mid MoE models that batch; 40B+
    # models run single-slot (maxNumSeqs = 1) per their catalog entries.
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

    # maxRequestTokens — Hard cap on max_tokens accepted from API clients
    # (--max-request-tokens). Server default: 32768.
    #
    # Unlike maxTokens, which only fills in a default when the client OMITS
    # max_tokens, this option ENFORCES a ceiling on whatever value the client
    # requests. If a client asks for max_tokens=100000, vllm-mlx clamps it to
    # this value and returns finish_reason: "length" once the cap is hit.
    #
    # Default 8192 — bounds runaway client-requested generation lengths
    # before they wait out a disconnect_guard timeout (tightened from null
    # after the 2026-05/06 pipe-timeout storm; see description). Set null to
    # restore the 32768 server ceiling when legitimately expensive
    # generations matter more than bounding a misconfigured caller.
    maxRequestTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 8192;
      description = "Hard cap on max_tokens accepted from clients. Null = vllm-mlx server default (32768). Default 8192 — rejects callers that request runaway generation lengths before they wait 5+ minutes for a `disconnect_guard` timeout. Tightened from `null` after the 2026-05-29 → 2026-06-03 pipe-timeout storm where pipes sending 80K-token prompts dominated the queue.";
    };
  };
}
