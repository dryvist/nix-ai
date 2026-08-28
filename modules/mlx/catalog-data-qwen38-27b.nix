# qwen38-27b — split out of catalog-data.nix for the per-file 12KB gate (same
# split-rather-than-exempt pattern as catalog-data-80b-instruct.nix). Merged
# into the same catalog attrset by catalog-data.nix; see that file for the
# entry schema and catalog-lib.nix for the shared serve-arg helpers.
let
  inherit (import ./catalog-lib.nix) block256 block512 swapFlags;
in
{
  # Resident Hermes goal judge and default small/midsize model.
  #
  # Drop-in successor to qwen36-27b-mxfp4: both are model_type qwen3_5_text with
  # an IDENTICAL attention topology — 64 layers split 16 full_attention /
  # 48 linear_attention, num_key_value_heads 4, head_dim 256 (read from each
  # model's own config.json on the headless host, 2026-08-14). Same geometry
  # means the incumbent's validated serve flags transfer verbatim; nothing
  # here is guessed.
  #
  # Note this family is HYBRID attention but is NOT qwen3_next: it does not hit
  # the mlx-lm#1162 paged-block reconstruction failure, which is why the
  # incumbent runs without hybridNoPaged and this entry does the same. Do not
  # "fix" that by adding hybridNoPaged on the strength of the layer_types field
  # alone — the incumbent has served this topology in production for weeks.
  #
  # Thinking is ON at the model's own baseline. Its reasoning is the reason it
  # was adopted, so serving it thinking-off gives up what it was chosen for —
  # but the kwarg cannot simply be dropped either: the chat template defaults
  # reasoning_effort to 'xhigh' when unset, and at xhigh it does not finish.
  #
  # All three measured on an isolated worker (the headless host, 2026-08-14),
  # weights proven from its process command line:
  #
  #   unset -> xhigh   0 answer chars, 16399 reasoning, "length" 3/3 (at 4096)
  #   low              10079 answer, 5051 reasoning, 3842 tokens, "stop" 3/3
  #   medium           13456 answer, 2334 reasoning, 4243 tokens, "stop"
  #
  # medium is chosen: it completes inside this worker's 8192-token budget and
  # produces the more substantial answer. It reasons LESS than low while
  # answering more, which is not a contradiction — medium injects NO
  # instruction at all. The prompt is 89 tokens at medium against 119 at low,
  # and that 30-token difference IS low's "keep your thinking brief" string.
  # medium is the model's unsteered baseline, not a step up a dial.
  #
  # What is NOT claimed: that either value is bounded. reasoning_effort is a
  # prompt string the model may ignore, so neither low nor medium is a budget
  # — only vllm-mlx's thinking_token_budget enforces a real ceiling. Do not
  # read this pin as protection against a long think.
  #
  # No tok/s figure is recorded here on purpose. Decode on this host measured
  # 17.4-27.3 across runs producing byte-identical output, so a single-run
  # throughput number for this entry would be noise.
  qwen38-27b = {
    model = "mlx-community/Qwen3.8-27B-4bit";
    weightGb = 16.1;
    # qwen3_5_text HYBRID: 64 layers, 16 full_attention / 48 linear_attention
    # (already stated above — full_attention_interval 4). Only the 16
    # full-attention layers carry paged KV; the 48 linear layers carry none.
    # perTokenKvBytes = 2*16*4*256*2 = 65536 B/token (64 KiB/token). Verified
    # against the model's own config.json (2026-08-27).
    kv = {
      kvLayers = 16;
      kvHeads = 4;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    # The model supports a native 262,144-token window. Production roles use
    # 131,072 so the remaining range is available for separately managed 200K
    # feasibility work rather than silently becoming a fleet default.
    contextWindowTokens = 131072;
    args = [
      "--chat-template-args"
      (builtins.toJSON {
        reasoning_effort = "medium";
      })
    ];
    # NO concurrencyLimit. The entry this replaced carried concurrencyLimit = 1
    # because it was a latency-sensitive judge that never needed concurrent
    # decode. This entry is the fleet brain every role resolves to, so pinning
    # it to 1 would make llama-swap serialize every request on the host.
    classes = {
      # Fleet-brain resident profile, matched to the entry it takes over from:
      # The 128k catalog window must also be admitted by the serving worker;
      # a lower request cap would turn the declared default into a client-only
      # hint and force long-context callers to fail before model dispatch.
      resident.flags = block512 // {
        cacheMemoryMb = 16384;
        maxNumSeqs = 8;
        maxRequestTokens = 131072;
      };
      swap.flags =
        block256
        // swapFlags
        // {
          cacheMemoryMb = 3072;
        };
    };
  };
}
