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

  # Same escape fixture with the residency budget widened to two workers. the
  # default maxResidentWorkers = 1 collapses every model into one
  # exclusive group so k_max stays 1; the tiered topology (persistent resident
  # beside a non-exclusive small tier, i.e. k_max = 2) survives only when a host
  # explicitly opts in by lowering memoryHardLimitGb to match. Both shapes are
  # asserted so neither can regress into the other silently.
  escapeTiered = import ../../modules/mlx/llama-swap-topology.nix { inherit (pkgs) lib; } {
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
    maxResidentWorkers = 2;
  };
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
    # At the default maxResidentWorkers = 1 the kept-small tier joins the
    # resident's exclusive group instead of sitting beside it, so only one worker
    # can hold weights at a time and k_max * memoryHardLimitGb stays under the
    # host wired ceiling. The old shape (persistent resident + non-exclusive
    # small tier) permitted two workers at the full per-worker budget, which is
    # the over-commit this default exists to prevent.
    assert assertMsg (
      escape.groups.mlx-models.members == [
        "brain"
        "sidekick"
      ]
    ) "escape: at k_max=1 the resident and kept-small models must share ONE group";
    assert assertMsg escape.groups.mlx-models.exclusive
      "escape: the merged group must stay exclusive so other groups cannot hold weights beside it";
    assert assertMsg escape.groups.mlx-models.swap
      "escape: the merged group must swap — members that do not evict each other defeat k_max=1";
    assert assertMsg (!escape.groups.mlx-models.persistent)
      "escape: the merged group must NOT be persistent — with one group there is nothing to protect it from, and persistence would pin weights across swaps";
    assert assertMsg (!(escape.groups ? mlx-small-models))
      "escape: no second group may exist at k_max=1 — a separate small tier is exactly the k_max=2 shape";
    # The opt-in tiered shape must still compile for hosts that lower
    # memoryHardLimitGb to fit two workers.
    assert assertMsg (
      escapeTiered.groups.mlx-models.members == [ "brain" ]
    ) "escapeTiered: the single resident must be the sole member of the pinned group";
    assert assertMsg escapeTiered.groups.mlx-models.persistent
      "escapeTiered: the single resident must be pinned persistent so a small load can't evict it";
    assert assertMsg (
      escapeTiered.groups.mlx-small-models.members == [ "sidekick" ]
    ) "escapeTiered: kept small models must form their own swap group";
    assert assertMsg (
      !escapeTiered.groups.mlx-small-models.persistent
    ) "escapeTiered: the kept-small swap group must be non-persistent (on-demand, idle-unloaded)";
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
