# MLX Module — the serving-limit derivation
#
# Every memory, concurrency, and cache limit the model servers run with is
# computed HERE, from a small set of inputs, and nowhere else. Before this file
# those values were literals spread across catalog entries, catalog-lib profiles
# and options-proxy, each hand-calculated once and then hand-synced forever —
# a shape that had already drifted (see the three notes below).
#
# The contract, and the reason to reach for this file rather than edit a number:
#
#   INPUT      a fact about hardware or a model, or a deliberate choice.
#              Written once, in one place.
#   CALIBRATION an empirical coefficient that cannot be derived from first
#              principles. Named, isolated, and TUNED HERE when reality
#              disagrees — never worked around at a call site.
#   DERIVED    computed below. Never hand-set, never overridden. If a derived
#              value is wrong, the fix is an input or a calibration constant,
#              because a literal at the call site is how this rotted last time.
#
# WHAT WAS WRONG BEFORE (2026-08-27), kept here because each is a live trap:
#
#   1. catalog-lib.nix documents
#        perTokenKvBytes = 2 * kvLayers * kvHeads * headDim * kvDtypeBytes
#      and the `kv` schema that feeds it — but the formula was never executed in
#      Nix. Every occurrence of perTokenKvBytes was a hand-evaluated result
#      pasted into a COMMENT. This file is the first code that computes it.
#
#   2. options-proxy.nix derived concurrencyLimitCeiling from four constants
#      that restate the catalog instead of reading it: peakWeightGiB = 31,
#      kvPerTokenDenseKiB = 64, maxGrantedRequestTokens = 65536. That last one
#      is the sharpest trap — raise a model's window and the ceiling meant to
#      protect memory keeps computing against the old number, with nothing
#      detecting the drift.
#
#   3. options-residency.nix states the invariant
#        maxResidentWorkers * memoryHardLimitGb <= host wired ceiling
#      in prose, warns that "2 workers at the default 99 GiB permits 198 GiB
#      against a 100 GiB ceiling, which over-commits it", and then leaves both
#      numbers to be set by hand. Co-residency therefore silently over-commits
#      unless a human remembers to lower the other number. Here it cannot:
#      memoryHardLimitGb is derived FROM the ceiling and k_max.
#
# ON THE NUMBERS: the calibration constants below are seeded from single
# observations on one host under uncontrolled load, not controlled benchmarks.
# They are directional, and they are expected to be wrong at the edges. That is
# precisely why they are isolated and labelled — tuning one of them is the
# supported way to respond to a measurement, and the reason none of their
# consequences are written down as literals anywhere else.
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
    # Metal buffers held per paged KV block per KV-bearing layer. Cannot be
    # derived from first principles — it depends on MLX allocator internals.
    #
    # SEEDED AT 1 AND DELIBERATELY UNCALIBRATED. The obvious anchor was
    # catalog-lib's "~98K buffers at maxNumSeqs 8 x 65K window", but that
    # figure is not yet trustworthy: catalog-data.nix records
    # perTokenKvBytes = 98304 B/token for an unrelated model, and two distinct
    # quantities carrying the same number is exactly how a hand-copied constant
    # loses its units. Calibrate this against a real buffer-exhaustion run
    # before treating headroom reported here as meaningful.
    bufferPerBlockPerLayer = 1;

    # Prompt-cache slots per in-flight stream. Each concurrent stream needs at
    # least its own slot or streams evict each other between turns; the
    # measured cost of getting this wrong was large (model-server-cmd.nix
    # records 0.22s warm vs 8.34s cold at 7k tokens with a single shared slot,
    # and re-prefill cost scales with context, so a long-context stream pays
    # far more). 2 gives each stream its slot plus one for an alternating
    # conversation rather than sizing exactly to concurrency.
    promptCacheSlotsPerStream = 2;

    # Fraction of a budget that may be committed, leaving room for the
    # allocator's own overhead and fragmentation. Applies to both the per-worker
    # memory budget and the Metal buffer ceiling.
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
    (divCeil (concurrency * windowTokens) blockSize)
    * kv.kvLayers
    * calibration.bufferPerBlockPerLayer;

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

  # ---- HOST-LEVEL DERIVATION ----------------------------------------------

  # memoryHardLimitGb, derived rather than declared.
  #
  # options-residency.nix carries the invariant
  #   maxResidentWorkers * memoryHardLimitGb <= host wired ceiling
  # and warns what happens when the two are set independently. Deriving the
  # per-worker budget FROM the ceiling makes over-commitment unrepresentable:
  # raising k_max necessarily lowers the per-worker budget, which is the
  # correction the prose asked a human to remember.
  #
  # The cushion is one whole GiB below the exact share, matching the existing
  # "99 GiB under the 100 GiB ceiling" posture at k_max = 1.
  memoryHardLimitGbFor =
    {
      hostWiredCeilingGb,
      maxResidentWorkers,
    }:
    lib.max 1 (hostWiredCeilingGb / maxResidentWorkers - 1);

  # ---- PER-MODEL DERIVATION ------------------------------------------------

  # Every serve limit for one model, from that model's facts plus its two
  # choices. The result is consumed directly by model-server-cmd.nix and the
  # llama-swap topology; nothing downstream recomputes or overrides any of it.
  #
  #   kv            { kvLayers; kvHeads; headDim; kvDtypeBytes; } from config.json
  #   weightGb      4-bit weight footprint
  #   concurrency   THE input — in-flight streams this model serves
  #   windowTokens  THE other input — max context per stream
  #   budgetGb      this worker's share, from memoryHardLimitGbFor
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

      # --- concurrency, one value reaching every layer that caps it.
      # maxNumSeqs is the model server's batch cap and concurrencyLimit is
      # llama-swap's in-flight cap; they were independent numbers before, which
      # meant llama-swap's default of 1 silently serialized a server configured
      # for 8. Both derive from `concurrency` here so they cannot disagree.
      maxNumSeqs = concurrency;
      decodeConcurrency = concurrency;
      promptConcurrency = concurrency;
      concurrencyLimit = concurrency;

      # --- context
      maxRequestTokens = windowTokens;

      # --- fitness, for assertions and for reporting a shape that cannot serve
      fitsMemory = committable >= inelastic;
      fitsBuffers = blockSize != null;
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
