# MLX Module — cacheMemoryMb resolution: derive vs pin. Split from derive.nix
# for the 12KB gate (same split-rather-than-exempt pattern as the catalog
# entries it serves). Adds no new derivation math — only the single entry
# point options-catalog.nix calls instead of forModel directly.
{ lib }:
let
  derive = import ./derive.nix { inherit lib; };
in
{
  # ---- SINGLE ENTRY POINT FOR cacheMemoryMb --------------------------------
  #
  # options-catalog.nix calls ONLY this: every catalog entry with a
  # cacheProvisioning attribute routes through one mechanism either way.
  #
  #   .concurrency = N   -> derive.nix's forModel computes it.
  #   .pinned = { mb; reason; tracking; } -> the literal stands. Use when
  #     forModel's computed value is unvalidated (bufferPerBlockPerLayer is
  #     deliberately uncalibrated — derive.nix's header) and the literal it
  #     would replace is empirically hardened instead (a prior production
  #     crash, not a guess): applying an unvalidated formula's output to a
  #     model with a real crash history is not this file's call to make
  #     alone. forModel still runs at concurrency=1 (derive.nix's standard
  #     comparison basis) so the pin's honest alternative is computed and
  #     exposed as derivedCacheMemoryMb — nothing to re-derive when the pin
  #     is later revisited.
  cacheMemoryMbFor =
    {
      kv,
      weightGb,
      windowTokens,
      budgetGb,
      cacheProvisioning,
    }:
    if cacheProvisioning ? pinned then
      cacheProvisioning.pinned
      // {
        cacheMemoryMb = cacheProvisioning.pinned.mb;
        derivedCacheMemoryMb =
          (derive.forModel {
            inherit
              kv
              weightGb
              windowTokens
              budgetGb
              ;
            concurrency = 1;
          }).cacheMemoryMb;
      }
    else
      derive.forModel {
        inherit
          kv
          weightGb
          windowTokens
          budgetGb
          ;
        inherit (cacheProvisioning) concurrency;
      };
}
