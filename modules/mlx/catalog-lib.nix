# Catalog schema + shared serve-arg helpers for catalog-data.nix.
#
# Split out of catalog-data.nix so each file stays under the 12KB file-size
# gate. The model entries live in catalog-data.nix and inherit these helpers.
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
#   kv               (optional) per-token KV-cache geometry for admission control.
#                    Fields fetched from the model's HF config.json:
#                      kvLayers     count of KV-BEARING attention layers. For a
#                                   standard model this is num_hidden_layers; for
#                                   the qwen3_next HYBRID it is ONLY the
#                                   full-attention layers = num_hidden_layers /
#                                   full_attention_interval (the recurrent/linear
#                                   layers carry NO paged-KV blocks — mlx-lm
#                                   qwen3_next.py make_cache gives them ArraysCache,
#                                   not KVCache), so counting all 48 would
#                                   over-reserve KV by 4x.
#                      kvHeads      num_key_value_heads (GQA KV head count)
#                      headDim      head_dim
#                      kvDtypeBytes bytes/element of the stored KV. 2 (fp16) unless
#                                   the serve profile sets --kv-cache-quantization
#                                   (store_true, default off; no resident does).
#                    perTokenKvBytes = 2 (K+V) * kvLayers * kvHeads * headDim
#                                      * kvDtypeBytes. Present on residents only —
#                                      the admission wrapper needs it to size the
#                                      GLOBAL paged-KV pool (--max-cache-blocks is
#                                      a whole-pool block count shared across all
#                                      concurrent sequences, not per-sequence).
#   args             family serve args, applied in every class
#   classes.<class>  validated profile: { flags = modelFlagOverrides attrs }
#     resident — preload-capable agent brain (host preload list still decides
#                what actually warms at boot)
#     swap     — on-demand, idle-unloaded, small caps
# An entry only offers the classes it has been validated for; requesting an
# unoffered class fails the eval.
{
  # Qwen3.6/Next MoE lineage: XML tool format needs hermes (qwen3_coder
  # mis-parses it → empty function.name repair storms) + qwen3 reasoning.
  qwenMoeGeneralParser = [
    "--tool-call-parser"
    "hermes"
    "--reasoning-parser"
    "qwen3"
  ];
  # Instruct (non-thinking) variants must NOT carry a reasoning parser: it
  # classifies the entire non-streaming completion as reasoning and strips it
  # (empty content, "Thinking-only response" under agent harnesses) while
  # streaming still works — the 2026-07-20 Hermes outage signature.
  qwenMoeInstructParser = [
    "--tool-call-parser"
    "hermes"
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
  # under the ceiling). Small swap models keep 256 (their 32K request cap
  # keeps block counts low); the 80B large brain runs 512 after 256 tripped
  # the ceiling four times under 2-way large-phase load on 2026-07-10 (see
  # its entry).
  block256 = {
    pagedCacheBlockSize = 256;
  };
  block512 = {
    pagedCacheBlockSize = 512;
  };
  # qwen3_next hybrid-attention family: the paged KV cache fails block
  # reconstruction on every multi-turn request (mlx-lm#1162), wedging the worker
  # into a full-context re-prefill each turn that the serving watchdog then
  # reaps. The standard non-paged KV cache reconstructs correctly, so these
  # models run paged off — the same escape hatch gpt-oss-120b uses for its own
  # paged-cache attention incompatibility. Prefix sharing needs the paged cache,
  # so it stays off too (already unsupported for this family). With paged off
  # there are no per-block Metal buffers, so block-size sizing no longer applies.
  hybridNoPaged = {
    pagedKvCache = false;
    enablePrefixCaching = false;
  };
  # Swap tier: on-demand, idle-unloaded, small caps.
  swapFlags = {
    autoUnloadIdleSeconds = 900;
    maxNumSeqs = 2;
    maxRequestTokens = 32768;
  };
}
