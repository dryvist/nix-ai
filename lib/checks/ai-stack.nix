# lib.aiStackModels regression tests
# Verifies the role → physical-id registry that is exported as a public flake output.
# ai-stack-models.nix is a function (parameterized by defaultLocalModelId); the
# aggregator passes a placeholder test id so the registry can be materialized.
{ pkgs, testLocalModelId }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  models = import ../ai-stack-models.nix { defaultLocalModelId = testLocalModelId; };

  expectedRoles = [
    "coding"
    "default"
    "large-context"
    "most-capable"
    "oss"
    "quickest"
    "tool-calling"
  ];

  actualRoles = builtins.sort builtins.lessThan (builtins.attrNames models);

  missingRoles = builtins.filter (r: !(builtins.hasAttr r models)) expectedRoles;
in
{
  # Verify the exported registry contains exactly the expected role set.
  ai-stack-models-keys =
    assert
      missingRoles == [ ] || throw "lib.aiStackModels missing roles: ${builtins.toJSON missingRoles}";
    assert
      actualRoles == expectedRoles
      || throw "lib.aiStackModels role set changed: expected ${builtins.toJSON expectedRoles}, got ${builtins.toJSON actualRoles}";
    helpers.mkMarker "check-ai-stack-models-keys" "lib.aiStackModels: ${toString (builtins.length expectedRoles)} roles verified";

  # Verify all physical IDs are non-empty mlx-community/ strings.
  ai-stack-models-physical-ids =
    let
      invalidEntries = builtins.filter (
        role:
        let
          physical = models.${role};
        in
        !(builtins.isString physical)
        || physical == ""
        || builtins.match "mlx-community/.+" physical == null
      ) (builtins.attrNames models);
    in
    assert
      invalidEntries == [ ]
      || throw "lib.aiStackModels physical IDs invalid for roles: ${builtins.toJSON invalidEntries}";
    helpers.mkMarker "check-ai-stack-models-physical-ids" "lib.aiStackModels: ${toString (builtins.length (builtins.attrNames models))} physical IDs verified as mlx-community/* strings";
}
