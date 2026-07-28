# programs.mlx.singleModel unit test — split from mlx.nix (12KB gate).
{ pkgs, src }:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  # programs.mlx.singleModel: one resident model, everything else disabled
  # (not deleted), and NO other model's physical id grafted onto the resident.
  # A request naming a disabled model must 404 rather than be answered by the
  # resident's weights under the requested name.
  #
  # `physicalIds` is the set of real model ids in these fixtures; the graft
  # invariant below is expressed against it rather than against a hardcoded
  # list, so renaming a fixture cannot quietly weaken the test.
  physicalIds = [
    "brain"
    "judge"
    "sidekick"
  ];
  graftedInto = aliases: builtins.filter (a: builtins.elem a physicalIds) aliases;
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
      sortedAliases == [ "default" ]
      || throw "singleModel: the resident must keep ONLY its own role aliases, got ${builtins.toJSON sortedAliases}";
    assert
      graftedInto topology.models.brain.aliases == [ ]
      || throw "singleModel: another model's physical id was grafted onto the resident as an alias: ${builtins.toJSON (graftedInto topology.models.brain.aliases)}";
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
    helpers.mkMarker "check-mlx-single-model-mode" "MLX single-model mode: one resident model keeping only its own role aliases, no physical-id graft, everything else disabled-not-deleted";

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
      escapeAliases == [ "default" ]
    ) "escape: the resident must keep ONLY its own role aliases";
    assert assertMsg (graftedInto escape.models.brain.aliases == [ ])
      "escape: no model's physical id may be grafted onto the resident — disabled ids must 404, not resolve to the resident";
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
    helpers.mkMarker "check-mlx-single-model-escape" "MLX singleModel escape: alwaysAvailableModels stay on-demand servable beside a pinned resident, no physical-id graft, others still disabled";

  # The client-side substitution probe. Wired here because it guards the same
  # invariant from the runtime side: the topology checks above prove no graft is
  # COMPILED, this proves a substitution would be VISIBLE if one occurred anyway.
  #
  # `&&`, never `;`. With a semicolon `touch $out` runs even when the test exits
  # non-zero, so the derivation succeeds and the check can never fail.
  mlx-model-resolution-note = pkgs.runCommand "check-mlx-model-resolution-note" { } ''
    ${pkgs.python3}/bin/python3 ${src}/tests/test-model-resolution-note.py && touch $out
  '';
}
