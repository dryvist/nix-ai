# programs.mlx.singleModel unit test — split from mlx.nix (12KB gate).
#
# The property under test is EXACT-NAME RESOLUTION: a request naming a model
# is served by that model's weights or it errors. Collapsing the catalog to
# one resident must never make another model's physical id resolve to the
# resident, because llama-swap answers 200 and echoes the *requested* name, so
# the substitution is invisible to every caller and every log downstream of
# it. That defect published one model's benchmark numbers under three other
# models' names (#1431).
#
# Deliberate role aliases ("default", "goal-judge") stay legal — they name a
# capability, not a checkpoint. What is banned is a *different model's
# physical id*, or a disabled model's own alias, resolving to the survivor.
{ pkgs }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs.lib) assertMsg;

  compile = import ../../modules/mlx/llama-swap-topology.nix { inherit (pkgs) lib; };

  # One fixture registry, reused by every mode below so the checks compare
  # like with like. `judge` carries a role alias of its own precisely so the
  # "a disabled model's alias must not leak either" case is covered.
  fixtureModels = {
    brain.aliases = [ "default" ];
    sidekick.aliases = [ "coding" ];
    judge.aliases = [ "goal-judge" ];
  };

  fixtureArgs = {
    residentModels = {
      brain.aliases = [ "default" ];
    };
    swapModels = {
      sidekick.aliases = [ "coding" ];
      judge.aliases = [ "goal-judge" ];
    };
    allModels = fixtureModels;
    groupSwap = false;
  };

  # programs.mlx.singleModel: one resident model, everything else disabled
  # (not deleted) and NOT reachable under any name.
  topology = compile (fixtureArgs // { singleModel = "brain"; });

  # alwaysAvailableModels escape: `sidekick` stays servable beside the single
  # resident, `judge` is still disabled, and the resident is pinned persistent.
  escape = compile (
    fixtureArgs
    // {
      singleModel = "brain";
      alwaysAvailableModels = [ "sidekick" ];
    }
  );

  sortedAliases = builtins.sort builtins.lessThan topology.models.brain.aliases;
  escapeAliases = builtins.sort builtins.lessThan escape.models.brain.aliases;

  # --- the reusable substitution probe -----------------------------------
  # Every name a caller could send that MUST NOT resolve: each disabled
  # model's physical id, plus each disabled model's own role aliases. Derived
  # from the compiled topology, not hand-listed, so it keeps covering new
  # fixture entries without anyone remembering to extend it.
  unservableNames =
    t:
    builtins.concatLists (
      pkgs.lib.mapAttrsToList (id: entry: [ id ] ++ (entry.aliases or [ ])) t.disabledModels
    );

  # Every name the emitted config WILL resolve: each live model's key plus
  # its aliases.
  resolvableNames =
    t:
    builtins.concatLists (
      pkgs.lib.mapAttrsToList (id: entry: [ id ] ++ (entry.aliases or [ ])) t.models
    );

  # The whole rule in one expression: nothing unservable is resolvable.
  leaked = t: pkgs.lib.intersectLists (unservableNames t) (resolvableNames t);
in
{
  mlx-single-model-mode =
    assert assertMsg (
      builtins.attrNames topology.models == [ "brain" ]
    ) "singleModel: exactly one model must stay in `models`";
    assert assertMsg (topology.models.brain.ttl == 0) "singleModel: the resident entry must have ttl=0";
    # The core regression. Before the fix this list was
    # [ "default" "judge" "sidekick" ] — the two disabled models' physical ids
    # grafted straight onto the survivor.
    assert assertMsg (sortedAliases == [
      "default"
    ]) "singleModel: the resident must keep ONLY its own role aliases; no other model's physical id may be grafted on";
    assert assertMsg (
      leaked topology == [ ]
    ) "singleModel: a disabled model's id/alias resolves to the resident — that is a silent substitution: ${builtins.toJSON (leaked topology)}";
    assert assertMsg (builtins.attrNames topology.disabledModels == [
      "judge"
      "sidekick"
    ]) "singleModel: every non-resident model must survive under disabledModels, not be deleted";
    assert assertMsg (
      topology.groups == { }
    ) "singleModel: the live `groups` key must be empty (meaningless with one model)";
    assert assertMsg (
      topology.disabledGroups ? mlx-models
    ) "singleModel: the persistent group definition must survive under disabledGroups";
    helpers.mkMarker "check-mlx-single-model-mode"
      "MLX single-model mode: one resident model serving only its own role aliases, every other model disabled-not-deleted and unreachable by name";

  mlx-single-model-escape =
    assert assertMsg (
      builtins.sort builtins.lessThan (builtins.attrNames escape.models) == [
        "brain"
        "sidekick"
      ]
    ) "escape: alwaysAvailableModels ids must stay servable in `models` beside the resident";
    assert assertMsg (
      builtins.attrNames escape.disabledModels == [ "judge" ]
    ) "escape: non-kept models must still be disabled, not deleted";
    assert assertMsg (escapeAliases == [
      "default"
    ]) "escape: the resident keeps only its own role aliases (neither kept-small nor disabled ids may be grafted on)";
    assert assertMsg (
      leaked escape == [ ]
    ) "escape: a disabled model's id/alias resolves to a live entry — silent substitution: ${builtins.toJSON (leaked escape)}";
    # A kept-small model is served by its OWN weights under its own name, so
    # its own id and alias must both still resolve — the rule bans
    # substitution, not legitimate serving.
    assert assertMsg (
      escape.models.sidekick.aliases == [ "coding" ]
    ) "escape: a kept-small model keeps serving under its own name and its own role alias";
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
    helpers.mkMarker "check-mlx-single-model-escape"
      "MLX singleModel escape: alwaysAvailableModels stay on-demand servable under their OWN names beside a pinned resident, others disabled and unreachable";
}
