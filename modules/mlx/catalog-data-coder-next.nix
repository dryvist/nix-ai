# qwen3-coder-next — split out of catalog-data.nix for the per-file 12KB gate,
# the same split-rather-than-exempt pattern as its 80B siblings. Merged into the
# catalog attrset by catalog-data.nix; see that file for the entry schema and
# catalog-lib.nix for the shared serve-arg helpers.
#
# DEFINED, NOT SELECTED. A catalog-data entry is inert until a host names it in
# `programs.mlx.catalog` — options-catalog.nix only ever looks at entries the
# host listed. So this ships without changing what any host serves, and a host
# opts in deliberately with its own residency review, which is what the
# 40B-plus policy below exists to force.
let
  inherit (import ./catalog-lib.nix) hybridNoPaged swapFlags;
in
{
  # Candidate coding brain, staged for a bench rather than adopted. It is the
  # coding-specialised member of the qwen3_next family whose Instruct sibling is
  # already the fleet brain, so the serving profile below is that sibling's, not
  # a fresh guess — same architecture, same measured constraints.
  #
  # WHY IT IS WORTH BENCHING: the 30B coder this estate serves today is fast and
  # well-formed single-stream but produces malformed tool calls under concurrency
  # and collapses in the first multi-turn round (mlx-benchmarks RANKINGS.md), so
  # it can only ever be a sidecar. This model is the same 3B-active shape at
  # 80B total, which is the axis that might carry tool-calling as well as speed.
  # Adopt it only on a bench that measures both, at concurrency 1 and 2.
  #
  # WEIGHTS MUST BE PRE-CACHED on the serving host — `hf download
  # mlx-community/Qwen3-Coder-Next-4bit` (41.8 GiB, 9 shards). Present on the
  # Studio's model volume since 2026-09-05.
  qwen3-coder-next = {
    model = "mlx-community/Qwen3-Coder-Next-4bit";
    weightGb = 42.0;
    # qwen3_next HYBRID, topology read from the model's own config.json and
    # identical to both 80B siblings: 48 layers, full_attention_interval=4, so
    # only 12 full-attention layers carry KV and the other 36 gated-delta-net
    # layers carry none. kvHeads=2, headDim=256.
    # perTokenKvBytes = 2*12*2*256*2 = 24576 B/token.
    kv = {
      kvLayers = 12;
      kvHeads = 2;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    args = [ ];
    # 40B+ single-slot policy, inherited from the siblings rather than re-argued:
    # this family aborts with metal::malloc resource-limit errors under
    # concurrent requests, and prefix-cache reconstruction is broken upstream
    # (mlx-lm#1162) so every tool turn full-reprefills. concurrencyLimit=1 makes
    # the proxy queue; maxNumSeqs=1 caps the engine batch so a proxy regression
    # cannot re-enable batching.
    concurrencyLimit = 1;
    # Swap only. A 42 GB candidate does not enter anyone's residency budget
    # before a bench says it earned the place — promote it to a resident class
    # in the same change that reports the numbers, never ahead of them.
    classes = {
      swap = {
        cacheProvisioning.pinned = {
          mb = 4096;
          reason = "sibling's live working value; unvalidated formula, family has a documented crash history under concurrency";
          tracking = "vikunja#106";
        };
        flags =
          swapFlags
          // hybridNoPaged
          // {
            maxNumSeqs = 1; # 40B+ single-slot policy (overrides swapFlags maxNumSeqs=2)
          };
      };
    };
  };
}
