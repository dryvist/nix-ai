# MLX Module — the serving-limit derivation
#
# Every memory/buffer limit a model server runs with is computed HERE from a
# small input set, not hand-set at a call site. Before this file the values
# were literals in catalog entries, catalog-lib, and options-proxy, hand-
# calculated once and hand-synced forever — already drifted (below).
#
#   INPUT       a hardware/model fact or deliberate choice. Written once.
#   CALIBRATION an empirical coefficient, not derivable from first
#               principles. Named, isolated, TUNED HERE when reality
#               disagrees — never worked around at a call site.
#   DERIVED     computed below, never hand-set/overridden. Wrong output ->
#               fix an input or calibration constant, not a call-site literal.
#
# WHAT WAS WRONG BEFORE (2026-08-27), each a live trap:
#
#   1. catalog-lib.nix documents
#        perTokenKvBytes = 2 * kvLayers * kvHeads * headDim * kvDtypeBytes
#      but never executed it — every occurrence was hand-evaluated into a
#      COMMENT. This file is the first code that computes it.
#
#   2. options-proxy.nix's concurrencyLimitCeiling restated the catalog
#      instead of reading it (peakWeightGiB=31, kvPerTokenDenseKiB=64,
#      maxGrantedRequestTokens=65536). The last one is sharpest: raise a
#      window and the memory ceiling keeps computing against the old number.
#
#   3. options-residency.nix states
#        maxResidentWorkers * memoryHardLimitGb <= host wired ceiling
#      in prose. NOT THIS FILE'S DERIVATION — nix-darwin's
#      hosts/common/residency-budget.nix already computes memoryHardLimitGb
#      from appleSiliconTunables.wiredLimitMb + k_max, same closure as the
#      sysctl read. Taken as a given INPUT here (forModel's budgetGb).
#
# WHAT THIS FILE DOES NOT OWN (found wiring it in, 2026-08-28): `maxNumSeqs`
# (engine batch-admission width) and `proxy.concurrencyLimit`/
# `serveConcurrency` (llama-swap's admission cap) are NOT `concurrency`
# below — an earlier version conflated them. Proof: today's real qwen38-27b
# values (maxNumSeqs=8, window=131072, weightGb=16.1) demand ~80 GiB in the
# old KV formula against a 48 GiB budget, yet this config runs fine today at
# cacheMemoryMb=16384. maxNumSeqs is a throughput ceiling the runtime paged-
# cache admission check enforces AT CALL TIME (docs/local-llm/memory-
# ceilings.mdx "load-time admission control"), not a promise of pre-reserved
# capacity for that many simultaneous streams. Admission width already has a
# single source: the ADR at d/decisions/llm-serving-concurrency-single-source
# (docs-starlight) plus the catalog's per-entry `concurrencyLimit`. This file
# sets neither — only sizing for a stated provisioning target (see
# `concurrency` on forModel).
#
# ON THE NUMBERS: calibration constants are seeded from single observations
# on one host under uncontrolled load, not controlled benchmarks — directional
# and expected wrong at the edges. That is why they are isolated and named:
# tuning one is the supported response to a measurement, and the reason none
# of their consequences are literals anywhere else.
{ lib }:
let
  # ---- PLATFORM FACTS ------------------------------------------------------

  # MLX's Metal buffer-count ceiling. Exceeding it raises
  # "Resource limit (499000) exceeded" — a BUFFER-COUNT failure, not a byte
  # OOM, which is why it is reachable at low memory use and why the lever
  # against it is block size rather than a smaller budget (nix-darwin#1609).
  metalBufferCeiling = 499000;

  # ---- CALIBRATION ---------------------------------------------------------
  # Empirical. Tune HERE against measurement; never compensate at a call site.

  calibration = {
    # Metal buffers held per paged KV block per KV-bearing layer. Depends on
    # MLX allocator internals, not derivable from first principles.
    #
    # SEEDED AT 1, DELIBERATELY UNCALIBRATED: no real buffer-exhaustion run
    # exists to fit it to yet (catalog-lib's "~98K buffers at maxNumSeqs 8 x
    # 65K window" and catalog-data.nix's unrelated-model
    # perTokenKvBytes=98304 B/token were checked 2026-08-28 and are
    # legitimately different quantities, not a units collision — but neither
    # is a calibration measurement). Fit to a real run before trusting the
    # headroom this reports.
    bufferPerBlockPerLayer = 1;

    # Prompt-cache slots per in-flight stream — each needs its own or streams
    # evict each other between turns (model-server-cmd.nix: 0.22s warm vs
    # 8.34s cold at 7k tokens, single shared slot; re-prefill cost scales with
    # context). 2 = own slot plus one for an alternating conversation.
    promptCacheSlotsPerStream = 2;

    # Committable fraction of a budget, leaving allocator overhead/
    # fragmentation headroom. Applies to the per-worker memory budget and the
    # Metal buffer ceiling alike.
    safetyFraction = 90; # percent

    # Practical decode concurrency on a single Apple GPU. Throughput collapses
    # before memory does, so this caps the memory-derived ceiling rather than
    # replacing it: tighten on memory, never loosen past operator judgment.
    # Carried forward unchanged from options-proxy.nix.
    operatorConcurrencyCap = 4;
  };

  # ---- HELPERS -------------------------------------------------------------

  divCeil = a: b: (a + b - 1) / b;
  pct = value: percent: (value * percent) / 100;

  gib = 1024 * 1024 * 1024;
  mib = 1024 * 1024;

  # perTokenKvBytes — the formula catalog-lib.nix documents, finally executed.
  #
  # kvLayers is the count of KV-BEARING layers, which for a hybrid-attention
  # model is ONLY its full-attention layers: the linear/recurrent layers get an
  # ArraysCache rather than a KVCache and hold no paged KV. Counting all layers
  # on such a model over-reserves KV several-fold, so this multiplies exactly
  # what the entry declares and never num_hidden_layers.
  perTokenKvBytes =
    kv:
    2 # K and V
    * kv.kvLayers
    * kv.kvHeads
    * kv.headDim
    * kv.kvDtypeBytes;

  # The smallest paged block size whose predicted buffer count stays under the
  # ceiling. Smaller blocks waste less KV on partial fills, so prefer the
  # smallest that fits rather than the largest available — but the candidates
  # ascend so that a shape needing bigger blocks still gets them instead of
  # failing. Returns null when nothing fits, which the assertions turn into an
  # eval error naming the shape rather than a runtime buffer exhaustion.
  blockSizeCandidates = [
    256
    512
    1024
    2048
  ];

  predictedBuffersFor =
    {
      kv,
      concurrency,
      windowTokens,
      blockSize,
    }:
    (divCeil (concurrency * windowTokens) blockSize) * kv.kvLayers * calibration.bufferPerBlockPerLayer;

  selectBlockSize =
    args:
    let
      budget = pct metalBufferCeiling calibration.safetyFraction;
      fits = blockSize: predictedBuffersFor (args // { inherit blockSize; }) <= budget;
      usable = lib.filter fits blockSizeCandidates;
    in
    if usable == [ ] then null else lib.head usable;
in
rec {
  inherit metalBufferCeiling calibration perTokenKvBytes;

  # ---- PER-MODEL DERIVATION ------------------------------------------------

  # Memory and buffer-count sizing for one model's PROMPT CACHE, from that
  # model's facts plus a stated provisioning target. Consumed by
  # model-server-cmd.nix for cacheMemoryMb/pagedCacheBlockSize only.
  #
  #   kv            { kvLayers; kvHeads; headDim; kvDtypeBytes; } from config.json
  #   weightGb      4-bit weight footprint
  #   concurrency   how many GENUINELY SIMULTANEOUS full-window streams to
  #                 guarantee cache capacity for — a provisioning target you
  #                 choose, NOT the engine's maxNumSeqs batch-admission width
  #                 and NOT proxy.concurrencyLimit/serveConcurrency. Those are
  #                 throughput ceilings enforced by the runtime admission
  #                 check at call time; this is a memory-sizing promise. The
  #                 two may legitimately differ by a wide margin (today's
  #                 fleet brain: maxNumSeqs=8 for throughput, but nobody
  #                 promises 8 simultaneous 131k-token conversations fit).
  #   windowTokens  max context per guaranteed stream
  #   budgetGb      this worker's memoryHardLimitGb — an INPUT taken as given
  #                 (nix-darwin's hosts/common/residency-budget.nix derives
  #                 it from the host ceiling and k_max; this file does not)
  forModel =
    {
      kv,
      weightGb,
      concurrency,
      windowTokens,
      budgetGb,
    }:
    let
      tokenBytes = perTokenKvBytes kv;
      totalTokens = concurrency * windowTokens;

      liveKvBytes = totalTokens * tokenBytes;

      promptCacheSlots = concurrency * calibration.promptCacheSlotsPerStream;
      # Sized to hold each slot's full window: a slot that cannot hold the
      # window it is caching for evicts mid-conversation, which is the
      # expensive failure this budget exists to prevent.
      promptCacheBytesUnclamped = promptCacheSlots * windowTokens * tokenBytes;

      # What remains for the prompt cache after weights and live KV are taken
      # out of this worker's committable share. The prompt cache is the only
      # elastic consumer here — weights and live KV are both required to serve
      # the declared shape at all — so it absorbs the shortfall rather than
      # failing the build, and the assertion below catches the case where even
      # the inelastic part does not fit.
      committable = pct (budgetGb * gib) calibration.safetyFraction;
      inelastic = (weightGb * gib) + liveKvBytes;
      promptCacheHeadroom = if committable > inelastic then committable - inelastic else 0;
      promptCacheBytes = lib.min promptCacheBytesUnclamped promptCacheHeadroom;

      blockSize = selectBlockSize { inherit kv concurrency windowTokens; };
      predictedBuffers =
        if blockSize == null then
          null
        else
          predictedBuffersFor {
            inherit
              kv
              concurrency
              windowTokens
              blockSize
              ;
          };
    in
    {
      # --- facts carried through, so a consumer never recomputes them
      inherit tokenBytes totalTokens;

      # --- memory
      inherit liveKvBytes promptCacheBytes promptCacheSlots;
      liveKvGb = liveKvBytes / gib;
      # model-server-cmd.nix wants MiB for --prompt-cache-bytes' sibling flag
      cacheMemoryMb = promptCacheBytes / mib;
      totalResidentBytes = inelastic + promptCacheBytes;

      # --- paged cache
      pagedCacheBlockSize = blockSize;
      maxCacheBlocks = if blockSize == null then null else divCeil totalTokens blockSize;
      inherit predictedBuffers;

      # --- fitness, for assertions and for reporting a shape that cannot serve
      fitsMemory = committable >= inelastic;
      fitsBuffers = blockSize != null;

      # maxNumSeqs / concurrencyLimit / maxRequestTokens are DELIBERATELY not
      # emitted here. maxRequestTokens is the catalog's own contextWindowTokens
      # field (a vllm-mlx generation guard already single-sourced there);
      # maxNumSeqs and concurrencyLimit are the ADR-governed admission width
      # (see the file header) — neither is this file's to set.
    };

  # ---- CEILING -------------------------------------------------------------

  # The replacement for options-proxy.nix's concurrencyLimitCeiling. Same
  # shape, but every input is read from the catalog rather than restated: the
  # peak weight and the largest granted window come from the enabled entries
  # themselves, so raising a window cannot leave the ceiling computing against
  # a stale one.
  concurrencyCeilingFor =
    {
      budgetGb,
      peakWeightGb,
      peakWindowTokens,
      peakKv,
    }:
    let
      headroomBytes = (budgetGb - peakWeightGb) * gib;
      perStreamBytes = peakWindowTokens * (perTokenKvBytes peakKv);
      memoryFit = if perStreamBytes <= 0 then 1 else lib.max 1 (headroomBytes / perStreamBytes);
    in
    lib.min calibration.operatorConcurrencyCap memoryFit;
}
