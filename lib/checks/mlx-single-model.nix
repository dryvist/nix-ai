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

  # alwaysAvailableModels escape: `sidekick` stays servable beside the single
  # resident, `judge` is still disabled, and the resident is pinned persistent.
  escape = import ../../modules/mlx/llama-swap-topology.nix { inherit (pkgs) lib; } {
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
    alwaysAvailableModels = [ "sidekick" ];
  };
  escapeAliases = builtins.sort builtins.lessThan escape.models.brain.aliases;
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

  mlx-single-model-escape =
    let
      inherit (pkgs.lib) assertMsg;
    in
    assert assertMsg (
      builtins.sort builtins.lessThan (builtins.attrNames escape.models) == [
        "brain"
        "sidekick"
      ]
    ) "escape: alwaysAvailableModels ids must stay servable in `models` beside the resident";
    assert assertMsg (
      builtins.attrNames escape.disabledModels == [ "judge" ]
    ) "escape: non-kept models must still be disabled, not deleted";
    assert assertMsg (
      escapeAliases == [
        "default"
        "judge"
      ]
    ) "escape: kept small models must NOT be aliased onto the resident (only truly-disabled ids are)";
    assert assertMsg (
      (escape.models.sidekick.ttl or null) == null
    ) "escape: kept small models stay on-demand (no forced ttl=0 resident promotion)";
    assert assertMsg (
      escape.groups.mlx-models.members == [ "brain" ]
    ) "escape: the single resident must be the sole member of the pinned group";
    assert assertMsg escape.groups.mlx-models.persistent
      "escape: the single resident must be pinned persistent so a small load can't evict it";
    assert assertMsg (
      escape.groups.mlx-small-models.members == [ "sidekick" ]
    ) "escape: kept small models must form their own swap group";
    assert assertMsg (
      !escape.groups.mlx-small-models.persistent
    ) "escape: the kept-small swap group must be non-persistent (on-demand, idle-unloaded)";
    helpers.mkMarker "check-mlx-single-model-escape" "MLX singleModel escape: alwaysAvailableModels stay on-demand servable beside a pinned resident, unaliased, others still disabled";
}
