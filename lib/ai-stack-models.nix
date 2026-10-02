# AI Stack — Role Registry (parameterized reader)
#
# Returns the canonical capability-class → physical model ID map for the
# host. The role NAMES are the role map's roles that name a local model
# (lib/role-map.nix, passed as `roleMap`); a role whose model is null (e.g. `embed`) is
# router-only and never registered locally. The role VALUES are populated by
# the caller via `defaultLocalModelId` — the locally-installed physical model
# id, never hardcoded in this repo.
#
# Flake-output usage from external consumers (read-only). NOTE: this is a
# function, not a static attrset. Callers must provide the id:
#
#   inputs.nix-ai.lib.aiStackModels {
#     defaultLocalModelId = <sourced from AI_MODEL_LOCAL_LLM>;
#   }
#
# (the flake output supplies `roleMap`; in-repo callers pass it themselves)
#
# Non-Nix consumers (orbstack-kubernetes, ansible, shell scripts) should
# read ~/.config/ai-stack/registry.json instead — that file is written
# from the configured `services.aiStack.models` (already populated) by
# home-manager activation.

{ defaultLocalModelId, roleMap }:
let
  inherit (roleMap) roles;
  roleNames = builtins.filter (role: roles.${role}.model != null) (builtins.attrNames roles);
in
builtins.listToAttrs (
  map (role: {
    name = role;
    value = defaultLocalModelId;
  }) roleNames
)
