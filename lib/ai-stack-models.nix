# AI Stack — Role Registry (parameterized reader)
#
# Returns the canonical capability-class → physical model ID map for the
# host. The role NAMES come from vars/ai-stack.nix (the stable taxonomy).
# The role VALUES are populated by the caller via `defaultLocalModelId` —
# the locally-installed physical model id, never hardcoded in this repo.
#
# Do NOT add data here. New role names go in vars/ai-stack.nix.
#
# Flake-output usage from external consumers (read-only). NOTE: this is a
# function now, not a static attrset. Callers must provide the id:
#
#   inputs.nix-ai.lib.aiStackModels {
#     defaultLocalModelId = <sourced from AI_MODEL_LOCAL_LLM>;
#   }
#
# The id itself is stored in:
#   - GitHub org variable `dryvist.AI_MODEL_LOCAL_LLM`
#   - Doppler `gh-workflow-tokens` (configs `prd` + `dryvist`),
#     secret `AI_MODEL_LOCAL_LLM`
#   - macOS no-password automation keychain, item `AI_MODEL_LOCAL_LLM`
#
# Non-Nix consumers (orbstack-kubernetes, ansible, shell scripts) should
# read ~/.config/ai-stack/registry.json instead — that file is written
# from the configured `services.aiStack.models` (already populated) by
# home-manager activation.

{ defaultLocalModelId }:
let
  roleNames = builtins.attrNames (import ../vars/ai-stack.nix).models;
in
builtins.listToAttrs (
  map (role: {
    name = role;
    value = defaultLocalModelId;
  }) roleNames
)
