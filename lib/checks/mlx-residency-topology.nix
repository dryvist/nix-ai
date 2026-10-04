# llama-swap groups against programs.mlx.maxResidentWorkers (k_max).
#
#   mlx-residency-topology  residents that fit k_max share a non-swapping
#                           persistent group with ttl = 0 (loaded together);
#                           residents that do not fit keep swapping and keep
#                           their ttl; k_max = 1 collapses everything into one
#                           swapping group.
{ pkgs }:
let
  inherit (pkgs) lib;
  inherit (lib) assertMsg;
  helpers = import ./helpers.nix { inherit pkgs; };

  topology =
    {
      resident,
      swap ? { },
      maxResidentWorkers,
    }:
    import ../../modules/mlx/llama-swap-topology.nix { inherit lib; } {
      residentModels = resident;
      swapModels = swap;
      allModels = resident // swap;
      groupSwap = true;
      singleModel = null;
      inherit maxResidentWorkers;
    };
  two = {
    brain = {
      aliases = [ "default" ];
      ttl = 900;
    };
    judge = {
      aliases = [ "judge" ];
      ttl = 900;
    };
  };
  ocr = {
    ocr = {
      aliases = [ ];
      ttl = 600;
    };
  };

  together = topology {
    resident = two;
    maxResidentWorkers = 2;
  };
  collapsed = topology {
    resident = two;
    maxResidentWorkers = 1;
  };
  overflow = topology {
    resident = two;
    swap = ocr;
    maxResidentWorkers = 2;
  };
in
{
  mlx-residency-topology =
    assert assertMsg (
      together.groups.mlx-models.members == [
        "brain"
        "judge"
      ]
      && !together.groups.mlx-models.swap
      && together.groups.mlx-models.persistent
    ) "k_max=2, two residents: the resident group must not swap, so both stay loaded";
    assert assertMsg (
      together.models.brain.ttl == 0
      && together.models.judge.ttl == 0
      && together.models.judge.aliases == [ "judge" ]
    ) "k_max=2, two residents: co-resident models must never idle out (ttl = 0)";
    assert assertMsg (
      builtins.attrNames collapsed.groups == [ "mlx-models" ]
      && collapsed.groups.mlx-models.swap
      && collapsed.groups.mlx-models.exclusive
      && !collapsed.groups.mlx-models.persistent
      && collapsed.models.judge.ttl == 900
    ) "k_max=1: every model must share one swapping group and keep its ttl";
    assert assertMsg (
      overflow.groups.mlx-models.swap
      && overflow.groups.mlx-swap-models.swap
      && overflow.models.brain.ttl == 900
      && overflow.models.ocr.ttl == 600
    ) "k_max=2, two residents plus a swap tier: residents must keep swapping and keep their ttl";
    helpers.mkMarker "check-mlx-residency-topology" "residents that fit maxResidentWorkers stay loaded together with ttl 0; otherwise they swap";
}
