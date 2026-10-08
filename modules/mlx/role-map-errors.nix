# Contract between a role map (lib/role-map.nix shape) and the model catalog.
# Returns a list of error strings; empty means the map is valid. Shared by the
# programs.mlx.roleMap assertion and lib/checks/mlx-role-map.nix.
{ catalog, roleMap }:
let
  inherit (roleMap) models roles hosts;
  inherit (builtins) attrNames concatMap filter;
  modelServing = import ../../lib/model-serving.nix;

  # Only chat models configured in the local MLX catalog need an MLX catalog
  # entry. Other serving metadata remains in the role map for its consumers.
  modelErrors = concatMap (
    key:
    let
      model = models.${key};
      hasCatalogEntry = builtins.hasAttr key catalog;
      catalogEntry = if hasCatalogEntry then catalog.${key} else null;
      hasMatchingCatalogEntry = hasCatalogEntry && (catalogEntry.model or null) == (model.id or null);
      inferredServing =
        if hasMatchingCatalogEntry then
          modelServing {
            catalogEntry = { };
            roleModel = model;
            mlxCatalogEntry = catalogEntry;
          }
        else
          { mlxChat = false; };
      mlxChat = model.mlxChat or inferredServing.mlxChat;
    in
    if hasCatalogEntry && !mlxChat then
      [ "model `${key}` has an MLX catalog entry without a chat-completion backend" ]
    else if !mlxChat then
      [ ]
    else if !hasCatalogEntry then
      [ "model `${key}` is not a catalog entry" ]
    else if catalog.${key}.model != model.id then
      [ "model `${key}` id ${model.id} differs from catalog ${catalog.${key}.model}" ]
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
