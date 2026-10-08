# The LLM role map: which model serves each router role and which models every
# host class keeps. Model concurrency comes from the shared model catalog.
# Role assignments are in dryvist/homelab-contracts
# ansible/roles/llm_roles/files/model-roles.json.
#
# `src` is the `homelab-contracts` flake input; every in-flake caller passes it
# (modules receive it via _module.args), so a consumer's `follows` decides the
# revision. The default reads the same input from this repo's flake.lock and
# exists only for files imported by path with no arguments
# (modules/litellm-local/aliases.nix, imported that way by other flakes).
{
  src ?
    let
      lock = builtins.fromJSON (builtins.readFile ../flake.lock);
    in
    fetchTree lock.nodes.${lock.nodes.root.inputs.homelab-contracts}.locked,
  mlxCatalog ? { },
}:
let
  roleMap = builtins.fromJSON (
    builtins.readFile "${src}/ansible/roles/llm_roles/files/model-roles.json"
  );
  catalog = builtins.fromJSON (
    builtins.readFile "${src}/ansible/roles/llm_model_catalog/files/model-catalog.json"
  );
  catalogModels = catalog.llm_model_catalog_models;
  models = builtins.mapAttrs (
    key: model:
    let
      matches = builtins.filter (entry: entry.name == model.id) catalogModels;
      catalogEntry =
        if builtins.length matches == 1 then
          builtins.head matches
        else
          throw "role map model `${key}` must match exactly one shared catalog entry for `${model.id}`";
      concurrency =
        catalogEntry.max_parallel_requests
          or (throw "shared catalog entry `${model.id}` for role-map model `${key}` is missing `max_parallel_requests`");
      serving = import ./model-serving.nix {
        inherit catalogEntry;
        roleModel = model;
        mlxCatalogEntry = mlxCatalog.${key} or null;
      };
    in
    if !(builtins.isInt concurrency) || concurrency < 1 then
      throw "shared catalog entry `${model.id}` for role-map model `${key}` must define a positive integer `max_parallel_requests`"
    else
      model // { inherit concurrency; } // serving
  ) roleMap.models;
in
roleMap // { inherit models; }
