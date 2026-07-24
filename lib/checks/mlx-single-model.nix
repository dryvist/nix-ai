# programs.mlx.singleModel unit test — split from mlx.nix (12KB gate).
{ pkgs }:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  # programs.mlx.singleModel: one resident model, everything else disabled
  # (not deleted), every other model's own id aliased onto the resident.
  topology = import ../../modules/mlx/llama-swap-topology.nix { inherit (pkgs) lib; } {
    residentModels = {
      brain.aliases = [ "default" ];
    };
    swapModels = {
      sidekick.aliases = [ "coding" ];
      judge.aliases = [ "goal-judge" ];
    };
    allModels = {
      brain.aliases = [ "default" ];
      sidekick.aliases = [ "coding" ];
      judge.aliases = [ "goal-judge" ];
    };
    groupSwap = false;
    singleModel = "brain";
  };
  sortedAliases = builtins.sort builtins.lessThan topology.models.brain.aliases;
in
{
  mlx-single-model-mode =
    assert
      builtins.attrNames topology.models == [ "brain" ]
      || throw "singleModel: exactly one model must stay in `models`";
    assert topology.models.brain.ttl == 0 || throw "singleModel: the resident entry must have ttl=0";
    assert
      sortedAliases == [
        "default"
        "judge"
        "sidekick"
      ]
      || throw "singleModel: aliases must include the resident's own roles plus every other model's own id";
    assert
      builtins.attrNames topology.disabledModels == [
        "judge"
        "sidekick"
      ]
      || throw "singleModel: every non-resident model must survive under disabledModels, not be deleted";
    assert
      topology.groups == { }
      || throw "singleModel: the live `groups` key must be empty (meaningless with one model)";
    assert
      topology.disabledGroups ? mlx-models
      || throw "singleModel: the persistent group definition must survive under disabledGroups";
    helpers.mkMarker "check-mlx-single-model-mode" "MLX single-model mode: one resident model, every alias routed to it, everything else disabled-not-deleted";
}
