{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
in
{
  herdr-disabled-apps-regression =
    let
      owners = {
        claude = "claude";
        codex = "codex";
        antigravity-cli = "antigravity-cli";
        opencode = "opencode";
        copilot-cli = "copilot";
        qwen-code = "qwen";
      };
      disabled = lib.mapAttrs (
        owner: _:
        (hmConfig.extendModules {
          modules = [
            (lib.setAttrByPath [ "programs" owner "enable" ] (
              if
                builtins.elem owner [
                  "opencode"
                  "copilot-cli"
                  "qwen-code"
                ]
              then
                false
              else
                lib.mkForce false
            ))
          ];
        }).config
      ) owners;
      explicit =
        (hmConfig.extendModules {
          modules = [ { programs.herdr.integrations.claude.enable = lib.mkForce false; } ];
        }).config;
      explicitEnabled =
        (hmConfig.extendModules {
          modules = [
            {
              programs.herdr.integrations.claude.enable = lib.mkForce true;
            }
          ];
        }).config;
      valid =
        owner: adapter:
        let
          c = disabled.${owner};
          herdrAssertions = builtins.filter (a: lib.hasInfix "Herdr" a.message) c.assertions;
        in
        !c.programs.herdr.integrations.${adapter}.enable && lib.all (a: a.assertion) herdrAssertions;
    in
    assert lib.all (owner: valid owner owners.${owner}) (lib.attrNames owners);
    assert explicit.programs.claude.enable && !explicit.programs.herdr.integrations.claude.enable;
    assert explicitEnabled.programs.herdr.integrations.claude.enable;
    assert explicitEnabled.programs.claude.enable;
    helpers.mkMarker "check-herdr-disabled-apps-regression" "Disabled apps do not select their Herdr integrations.";

}
