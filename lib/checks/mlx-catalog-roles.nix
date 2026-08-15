# Role-registry regression tests.
#
# `programs.mlx.catalog.<entry>.roles` is a free-form list of strings — nothing
# validates a role name against vars/ai-stack.nix. What vars/ai-stack.nix
# governs is which roles EXIST on every host: each name there is populated from
# services.aiStack.defaultLocalModelId and compiled into a llama-swap alias, so
# a consumer can name the role on a host that has not pinned it. These checks
# hold both halves of that contract for `small`, and hold the line that adding
# a registry name does not weaken the one-entry-per-role assertion.
{
  pkgs,
  hmConfigSmallRole,
  hmConfigDupRole,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  small9b = "mlx-community/Qwen3.5-9B-OptiQ-4bit";

  # The catalog's one-entry-per-role assertion, located by its message rather
  # than by list index so an unrelated assertion landing beside it cannot make
  # this check silently read a different one.
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
      throw "mlx-catalog-roles: expected exactly one catalog role-uniqueness assertion, found ${toString (builtins.length matches)}";

  # Every role in the registry must resolve to a served backend that lists it as
  # an alias — the existing programs.mlx assertion. Read the same way.
  rolesCompileOf =
    hm:
    let
      matches = builtins.filter (
        a: builtins.match ".*compile into that llama-swap backend's aliases.*" a.message != null
      ) hm.config.assertions;
    in
    if builtins.length matches == 1 then
      (builtins.head matches).assertion
    else
      throw "mlx-catalog-roles: expected exactly one role-compiles-to-alias assertion, found ${toString (builtins.length matches)}";

  smallStack = hmConfigSmallRole.config.services.aiStack;
in
{
  mlx-catalog-roles =
    assert
      builtins.hasAttr "small" smallStack.models
      || throw "role registry: `small` must exist in services.aiStack.models on every host, assigned or not — that is what makes it a stable alias instead of a per-host name";
    assert
      smallStack.roleOverrides.small or null == small9b
      || throw "role registry: a catalog entry declaring roles = [ \"small\" ] must resolve the role to that entry's physical model id";
    assert
      smallStack.models.small == small9b
      || throw "role registry: the catalog role override must win over the defaultLocalModelId-populated registry entry";
    assert
      rolesCompileOf hmConfigSmallRole
      || throw "role registry: `small` must compile into a llama-swap backend that lists it as an alias — a role with no backend 404s the caller it was added for";
    assert
      uniquenessOf hmConfigSmallRole
      || throw "role registry: a single entry holding `small` must satisfy the one-entry-per-role assertion";
    # The duplicate-role config must not merely report a false assertion — the
    # module system must refuse to produce a config at all, so tryEval is the
    # only way to observe it. A `success = true` here means a host could ship
    # two entries fighting over one role name.
    assert
      !(builtins.tryEval (uniquenessOf hmConfigDupRole)).success
      || throw "role registry: two enabled catalog entries claiming the same role must still fail the one-entry-per-role assertion — adding a registry name must not weaken it";
    helpers.mkMarker "check-mlx-catalog-roles" "role registry: `small` exists, resolves through the catalog, compiles to a llama-swap alias, and stays uniqueness-checked";
}
