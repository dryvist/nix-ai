#
# MLX Module — Concurrency and batching options
#
# Complete parameter reference from `vllm-mlx serve --help`.
# 0.2.9 fixed the 0.2.8 MLLM detection bug for Qwen3-class models, so
# continuous batching + maxNumSeqs are now defaults rather than opt-in.
#
{ lib, ... }:
{
  options.programs.mlx = {
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
    # See dryvist/nix-ai#1234.
    defaultRepetitionPenalty = lib.mkOption {
      type = lib.types.nullOr (lib.types.numbers.between 1.0 2.0);
      default = null;
      example = 1.05;
      description = "Server-side default repetition penalty applied to every request (vllm-mlx --default-repetition-penalty). Set this instead of injecting a per-request penalty at the router: a penalty is a logits processor, and mixing processor-ful with processor-free requests in one batch wedges mlx_lm's batch generator (nix-ai#1234). Null = upstream default (no penalty), which is uniform and therefore also safe.";
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
