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
#   contextWindowTokens (optional) maximum accepted prompt-plus-generation
#                    tokens advertised to clients and used for conservative
#                    admission sizing. It is distinct from maxRequestTokens,
#                    which is a vllm-mlx generation guard.
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
#   architecture     (required on cluster entries) the model's config.json
#                    model_type, verbatim. Read by the clusterMode assertions
#                    to check shardingMode: mlx-lm's pipeline and tensor-parallel
#                    paths support disjoint architecture sets, and the wrong
#                    choice is silent — no split, full model on every rank.
#   backend          (optional) the model server this entry MUST run on, when
#                    the host backend cannot serve it at all — vision-language
#                    models need mlx_vlm.server because mlx_lm.server has no
#                    image input path. Compiles to programs.mlx.modelBackends.
#                    Omit for every text model: absent means "inherit
#                    programs.mlx.modelServerBackend". An entry that sets this
#                    must NOT reuse swapFlags below — those are mlx_lm serve
#                    flags and no other backend accepts them.
#   args             family serve args, applied in every class
#   classes.<class>  validated profile: { flags = modelFlagOverrides attrs }
#     resident — preload-capable agent brain (host preload list still decides
#                what actually warms at boot)
#     swap     — on-demand, idle-unloaded, small caps
# An entry only offers the classes it has been validated for; requesting an
# unoffered class fails the eval.
#
# KV-QUANT / MTP FLAGS: DO NOT ADD to normal catalog entries. Measured against the
# deployed release mlx-lm 0.31.3 wrapper's own --help (2026-08): no
# --kv-bits/--kv-group-size, no MTP flag exists on the release server at all.
# The backend is official mlx-lm only (vllm-mlx disabled, enforced by
# lib/checks/mlx-catalog.nix); #1334's KV-quant half is not actionable until
# mlx-lm ships the flags, and its MTP half is vllm-mlx-only and stays
# unavailable unless that backend is re-enabled. `modelMtpProfiles` provides a
# separate, opt-in c1-only experimental contract when a served snapshot and
# backend have both been verified. A future git-wheel
# serverVariant (staged DeepSeek rollout) adds --mtp but drops
# --harmony-tool-parser — never select it for gpt-oss.
{
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
