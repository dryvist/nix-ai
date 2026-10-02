# Contract between a role map (lib/role-map.nix shape) and the model catalog.
# Returns a list of error strings; empty means the map is valid. Shared by the
# programs.mlx.roleMap assertion and lib/checks/mlx-role-map.nix.
{ catalog, roleMap }:
let
  inherit (roleMap) models roles hosts;
  inherit (builtins) attrNames concatMap filter;

  # Every map model is a catalog entry serving the same physical id.
  modelErrors = concatMap (
    key:
    if !(catalog ? ${key}) then
      [ "model `${key}` is not a catalog entry" ]
    else if catalog.${key}.model != models.${key}.id then
      [ "model `${key}` id ${models.${key}.id} differs from catalog ${catalog.${key}.model}" ]
    else
      [ ]
  ) (attrNames models);

  # A dense model serves one request at a time.
  denseErrors = map (key: "dense model `${key}` must have concurrency 1") (
    filter (key: (models.${key}.dense or false) && models.${key}.concurrency != 1) (attrNames models)
  );

  # Every model a host class keeps, and every role it resolves (with the
  # class's own overrides applied), names a declared model.
  hostErrors = concatMap (
    class:
    let
      host = hosts.${class};
      effectiveRoles = roles // (host.roles or { });
      kept = host.resident ++ host.swap;
      badKept = filter (key: !(models ? ${key})) kept;
      badRoles = filter (
        role: effectiveRoles.${role}.model != null && !(models ? ${effectiveRoles.${role}.model})
      ) (attrNames effectiveRoles);
    in
    map (key: "host class `${class}` keeps undeclared model `${key}`") badKept
    ++ map (role: "role `${role}` on host class `${class}` names an undeclared model") badRoles
  ) (attrNames hosts);
in
modelErrors ++ denseErrors ++ hostErrors
