#
# MLX Module — batch width and token caps.
#
# maxNumSeqs and maxRequestTokens are catalog class-profile keys; the mlx-lm
# command builder does not emit them. maxTokens reaches mlx_lm as --max-tokens.
#
{ lib, ... }:
{
  options.programs.mlx = {
    # maxNumSeqs — Max concurrent sequences (--max-num-seqs).
    # Default: 4. The
    # 8 GB (8192 MB) default cache plus prefix sharing holds 4 concurrent
    # sequences comfortably across the small/mid MoE models that batch; 40B+
    # models run single-slot (maxNumSeqs = 1) per their catalog entries.
    maxNumSeqs = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 4;
      description = "Max concurrent sequences. Catalog profile key; not emitted by the mlx-lm builder.";
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
      description = "Default max tokens when client omits max_tokens. Null = 8192 (model-server-cmd.nix).";
    };

    # maxRequestTokens — Hard cap on max_tokens accepted from API clients
    # (--max-request-tokens). Server default: 32768.
    #
    # Unlike maxTokens, which only fills in a default when the client OMITS
    # max_tokens, this option ENFORCES a ceiling on whatever value the client
    # requests. If a client asks for max_tokens=100000, the server clamps it to
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
      description = "Hard cap on max_tokens accepted from clients. Null = no cap. Default 8192 — rejects callers that request runaway generation lengths before they wait 5+ minutes for a `disconnect_guard` timeout. Tightened from `null` after the 2026-05-29 → 2026-06-03 pipe-timeout storm where pipes sending 80K-token prompts dominated the queue.";
    };
  };
}
