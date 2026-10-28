# herdr config.toml delivery-mode regression test
#
# mutableSettings = true merges config.toml at activation; false links it from
# the Nix store. Both modes are evaluated and their activation entry and
# home.file entry are asserted, then forced so a lazy value cannot hide a failure.
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.herdr;
in
{
  herdr-settings-modes-regression =
    let
      configPath = "${cfg.configDir}/config.toml";
      mutableHome = hmConfig.config.home;
      immutableHmConfig = hmConfig.extendModules {
        modules = [ { programs.herdr.mutableSettings = false; } ];
      };
      immutableCfg = immutableHmConfig.config.programs.herdr;
      immutableHome = immutableHmConfig.config.home;
    in
    assert cfg.mutableSettings;
    assert lib.hasAttr "herdrConfigMerge" mutableHome.activation;
    assert !(lib.hasAttr configPath mutableHome.file);
    assert !immutableCfg.mutableSettings;
    assert !(lib.hasAttr "herdrConfigMerge" immutableHome.activation);
    assert lib.hasAttr configPath immutableHome.file;
    assert builtins.deepSeq mutableHome.activation.herdrConfigMerge.data true;
    assert builtins.deepSeq "${immutableHome.file.${configPath}.source}" true;
    helpers.mkMarker "check-herdr-settings-modes-regression" "herdr config.toml merge and store-link modes evaluate as declared.";
}
