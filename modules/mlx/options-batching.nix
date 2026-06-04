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
    # Left null by default — keeps the 32768 server ceiling intact so
    # legitimate expensive generations remain possible. Set to a positive
    # integer only when you specifically need to cap client-requested
    # generation length (e.g. cost control on a shared environment, or
    # bounding wasted compute on a pathologically misconfigured caller).
    maxRequestTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 8192;
      description = "Hard cap on max_tokens accepted from clients. Null = vllm-mlx server default (32768). Default 8192 — rejects callers that request runaway generation lengths before they wait 5+ minutes for a `disconnect_guard` timeout. Tightened from `null` after the 2026-05-29 → 2026-06-03 pipe-timeout storm where pipes sending 80K-token prompts dominated the queue.";
    };
  };
}
