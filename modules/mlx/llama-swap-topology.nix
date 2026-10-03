# Pure model/group topology compiler — split from default.nix so
# lib/checks/mlx.nix can unit-test it directly (same pattern as
# model-server-cmd.nix). Two modes:
#   singleModel == null -> normal multi-model registry (models + groups).
#   singleModel != null -> single-model mode: only that physical id is
#     servable (ttl=0), keeping ONLY its own role aliases; everything else is
#     kept but demoted to disabledModels/disabledGroups (llama-swap ignores
#     those keys) — disable, never delete. A caller naming a disabled model
#     gets a 404, never the resident's weights under the requested name.
#     Escape hatch: alwaysAvailableModels names small physical ids that stay
#     servable (on-demand swap tier) beside the single resident instead of
#     being disabled. Empty (default) -> byte-identical to the historical
#     single-model emission.
#
#     WHETHER A LOAD EVICTS ANOTHER MODEL DEPENDS ON maxResidentWorkers
#     (k_max). At k_max = 1 every model shares ONE swapping group, so any
#     load evicts the previous worker. At k_max >= 2 the tiered shape applies:
#     a persistent resident group beside a non-exclusive swap tier. The
#     resident group stops swapping when every resident plus one swap-tier
#     worker fits k_max, so those residents stay loaded together with
#     ttl = 0; otherwise it swaps (groupSwap) and holds one worker.
#     lib/checks/mlx-single-model.nix and lib/checks/mlx-residency-topology.nix
#     assert these shapes.
{ lib }:
{
  residentModels,
  swapModels,
  allModels,
  groupSwap,
  singleModel,
  alwaysAvailableModels ? [ ],
  maxResidentWorkers ? 1,
}:
let
  # The memory invariant is k_max * memoryHardLimitGb <= host wired ceiling,
  # where k_max is how many workers can hold weights at once. k_max = 1
  # collapses every model into one swapping group.
  collapseToOne = maxResidentWorkers == 1;

  # Residents stay loaded together when all of them, plus one swap-tier
  # worker, fit k_max.
  swapTierWorkers = if swapModels == { } then 0 else 1;
  residentsFit =
    builtins.length (builtins.attrNames residentModels) + swapTierWorkers <= maxResidentWorkers;
  residentSwap = groupSwap && !residentsFit;
  # Residents that never evict each other also never idle out.
  pinResidents = !collapseToOne && !residentSwap;

  # swap is forced true when collapsed: a single group whose members do not
  # evict each other would keep both resident and defeat the whole point.
  mergedGroups = {
    mlx-models = {
      swap = true;
      exclusive = true;
      persistent = false;
      members = builtins.attrNames residentModels ++ builtins.attrNames swapModels;
    };
  };

  tieredGroups = {
    mlx-models = {
      swap = residentSwap;
      exclusive = true;
      persistent = true;
      members = builtins.attrNames residentModels;
    };
  }
  // lib.optionalAttrs (swapModels != { }) {
    mlx-swap-models = {
      swap = true;
      exclusive = false;
      persistent = false;
      members = builtins.attrNames swapModels;
    };
  };

  groups = if collapseToOne then mergedGroups else tieredGroups;
in
if singleModel != null then
  let
    # Small models that stay servable in single-model mode: filtered to real
    # registry keys, and never the resident itself.
    keptSmall = lib.filter (id: id != singleModel && allModels ? ${id}) alwaysAvailableModels;
    smallModels = lib.genAttrs keptSmall (id: allModels.${id});
    keep = [ singleModel ] ++ keptSmall;
  in
  {
    models = {
      # The resident keeps ONLY its own role aliases. Grafting other models'
      # physical ids on here is banned: it made llama-swap answer a request
      # naming model A with model B's weights, 200 OK and the requested name
      # echoed back, which published one model's throughput under two other
      # models' names. A request for a disabled model must 404.
      ${singleModel} = allModels.${singleModel} // {
        ttl = 0;
        aliases = lib.unique (allModels.${singleModel}.aliases or [ ]);
      };
    }
    // smallModels;
    disabledModels = removeAttrs allModels keep;
    # No small models -> groups = {} (historical emission). With small models,
    # pin the single resident persistent so an on-demand small load beside it
    # never evicts it, and keep the small tier non-persistent/non-exclusive.
    #
    # That pairing is the same k_max = 2 shape as the multi-model branch —
    # a persistent resident plus a non-exclusive small tier means two workers
    # hold weights at once. Under maxResidentWorkers = 1 the small tier joins
    # the resident's group instead, so an on-demand small load evicts the
    # resident rather than sitting beside it.
    groups = lib.optionalAttrs (keptSmall != [ ]) (
      if collapseToOne then
        {
          mlx-models = {
            swap = true;
            exclusive = true;
            persistent = false;
            members = keep;
          };
        }
      else
        {
          mlx-models = {
            swap = groupSwap;
            exclusive = true;
            persistent = true;
            members = [ singleModel ];
          };
          mlx-small-models = {
            swap = true;
            exclusive = false;
            persistent = false;
            members = keptSmall;
          };
        }
    );
    disabledGroups = groups;
  }
else
  {
    models =
      allModels
      // lib.optionalAttrs pinResidents (
        lib.mapAttrs (id: _: allModels.${id} // { ttl = 0; }) residentModels
      );
    # Merge the two group definitions INSIDE `groups` (disjoint keys), not via
    # an outer `//` on the whole config set. `//` is a shallow update: two
    # sibling `groups.<name>` paths in `a // b` make `b`'s `groups` replace
    # `a`'s wholesale, so the persistent resident group would vanish whenever
    # the swap tier is non-empty — collapsing coder/OptiQ/gpt-oss into
    # llama-swap's implicit swap default and evicting a resident on every
    # cross-model request.
    inherit groups;
  }
