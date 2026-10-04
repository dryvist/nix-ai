# Catalog role mapping and uniqueness regression checks.
{
  pkgs,
  hmConfigSmallRole,
  hmConfigDupRole,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  small9b = "mlx-community/MiMo-V2.6-Distill-Qwen-9B-OptiQ-4bit";
  uniquenessOf =
    hm:
    let
      matches = builtins.filter (
        a: builtins.match ".*each logical role may be assigned to only one.*" a.message != null
      ) hm.config.assertions;
    in
    if builtins.length matches == 1 then
      (builtins.head matches).assertion
    else
      throw "mlx-catalog-roles: expected one catalog role-uniqueness assertion, found ${toString (builtins.length matches)}";
  smallStack = hmConfigSmallRole.config.services.aiStack;
in
{
  mlx-catalog-roles =
    assert
      builtins.hasAttr "small" smallStack.models
      || throw "role registry: `small` must exist in services.aiStack.models on every host";
    assert
      smallStack.roleOverrides.small or null == small9b
      || throw "role registry: a catalog entry declaring roles = [ \"small\" ] must resolve to that entry's physical model id";
    assert
      smallStack.models.small == small9b
      || throw "role registry: the catalog role override must win over the default role map";
    assert
      uniquenessOf hmConfigSmallRole
      || throw "role registry: one entry holding `small` must satisfy the role uniqueness assertion";
    assert
      !(builtins.tryEval (uniquenessOf hmConfigDupRole)).success
      || throw "role registry: two catalog entries claiming the same role must still fail evaluation";
    helpers.mkMarker "check-mlx-catalog-roles" "role registry: `small` resolves through the catalog and duplicate role ownership fails";
}
