{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.herdr;
  home = hmConfig.config.home;
in
{
  herdr-settings-modes-regression =
    assert lib.hasAttr "${cfg.configDir}/config.toml" home.file;
    assert !(lib.hasAttr "herdrConfigMerge" home.activation);
    assert builtins.deepSeq "${home.file."${cfg.configDir}/config.toml".source}" true;
    helpers.mkMarker "check-herdr-settings-modes-regression" "Herdr config.toml is declaratively linked.";
}
