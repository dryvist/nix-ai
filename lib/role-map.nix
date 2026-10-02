# The LLM role map: which model serves each router role, each model's
# concurrency, and which models every host class keeps. Canonical copy is
# dryvist/homelab-contracts ansible/roles/llm_roles/files/model-roles.json.
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
}:
builtins.fromJSON (builtins.readFile "${src}/ansible/roles/llm_roles/files/model-roles.json")
