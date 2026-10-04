# Shared model limits from the locked homelab-contracts input.
let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  src = builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.homelab-contracts}.locked;
  models =
    (builtins.fromJSON (
      builtins.readFile "${src}/ansible/roles/llm_model_catalog/files/model-catalog.json"
    )).llm_model_catalog_models;
in
builtins.listToAttrs (
  map (model: {
    name = model.name;
    value = model;
  }) models
)
