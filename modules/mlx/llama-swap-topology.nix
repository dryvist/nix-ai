# Pure model/group topology compiler — split from default.nix so
# lib/checks/mlx.nix can unit-test it directly (same pattern as
# model-server-cmd.nix). Two modes:
#   singleModel == null -> normal multi-model registry (models + groups).
#   singleModel != null -> single-model mode: only that physical id is
#     servable (ttl=0, keeping its OWN role aliases and nothing else);
#     everything else is kept but demoted to disabledModels/disabledGroups
#     (llama-swap ignores those keys) — disable, never delete. A request
#     naming a disabled model's id therefore 404s, naming the model it asked
#     for, instead of being served the resident's weights.
#     Escape hatch: alwaysAvailableModels names small physical ids that stay
#     servable (on-demand swap tier) beside the single resident instead of
#     being disabled — the resident is pinned persistent so a small-model
#     load can never evict it. Empty (default) -> byte-identical to the
#     historical single-model emission.
{ lib }:
{
  residentModels,
  swapModels,
  allModels,
  groupSwap,
  singleModel,
  alwaysAvailableModels ? [ ],
}:
let
  groups = {
    mlx-models = {
      swap = groupSwap;
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
      # EXACT-NAME RESOLUTION. The resident keeps its own deliberate role
      # aliases ("default", "goal-judge", …) — those name a capability and
      # have always meant "whatever currently serves this role". It must NOT
      # inherit any *other model's physical id* as an alias.
      #
      # This previously grafted every disabled model's id onto this entry, so
      # a request for e.g. a 120B returned the resident's weights with a 200
      # and the requested name echoed back in the response. Nothing
      # downstream could tell. It attributed one model's benchmark numbers to
      # three others and those results were published (#1431). A model that
      # is not loaded must 404, naming what was asked for.
      ${singleModel} = allModels.${singleModel} // {
        ttl = 0;
      };
    }
    // smallModels;
    disabledModels = removeAttrs allModels keep;
    # No small models -> groups = {} (historical emission). With small models,
    # pin the single resident persistent so an on-demand small load beside it
    # never evicts it, and keep the small tier non-persistent/non-exclusive.
    groups = lib.optionalAttrs (keptSmall != [ ]) {
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
    };
    disabledGroups = groups;
  }
else
  {
    models = allModels;
    # Merge the two group definitions INSIDE `groups` (disjoint keys), not via
    # an outer `//` on the whole config set. `//` is a shallow update: two
    # sibling `groups.<name>` paths in `a // b` make `b`'s `groups` replace
    # `a`'s wholesale, so the persistent resident group would vanish whenever
    # the swap tier is non-empty — collapsing coder/OptiQ/gpt-oss into
    # llama-swap's implicit swap default and evicting a resident on every
    # cross-model request.
    inherit groups;
  }
