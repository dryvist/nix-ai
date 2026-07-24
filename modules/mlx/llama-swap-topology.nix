# Pure model/group topology compiler — split from default.nix so
# lib/checks/mlx.nix can unit-test it directly (same pattern as
# model-server-cmd.nix). Two modes:
#   singleModel == null -> normal multi-model registry (models + groups).
#   singleModel != null -> single-model mode: only that physical id is
#     servable (ttl=0, aliased to every other model's own id so any caller
#     naming any known model still resolves to it); everything else is kept
#     but demoted to disabledModels/disabledGroups (llama-swap ignores those
#     keys) — disable, never delete.
{ lib }:
{
  residentModels,
  swapModels,
  allModels,
  groupSwap,
  singleModel,
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
  {
    models = {
      ${singleModel} = allModels.${singleModel} // {
        ttl = 0;
        aliases = lib.unique (
          (allModels.${singleModel}.aliases or [ ])
          ++ (lib.filter (id: id != singleModel) (builtins.attrNames allModels))
        );
      };
    };
    disabledModels = removeAttrs allModels [ singleModel ];
    groups = { };
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
