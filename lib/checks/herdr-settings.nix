{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  empty =
    (hmConfig.extendModules {
      modules = [ { programs.herdr.settings = lib.mkForce { }; } ];
    }).config;
  configured =
    (hmConfig.extendModules {
      modules = [
        {
          programs.herdr = {
            mutableSettings = lib.mkForce false;
            settings.theme.name = "test";
          };
        }
      ];
    }).config;
  consumer =
    (hmConfig.extendModules {
      modules = [
        {
          programs.herdr = {
            mutableSettings = lib.mkForce false;
            settings.remote.manage_ssh_config = false;
          };
        }
      ];
    }).config;
in
{
  herdr-config-check = pkgs.runCommand "check-herdr-composed-config" { } ''
    HERDR_CONFIG_PATH=${consumer.xdg.configFile."herdr/config.toml".source} \
      ${lib.getExe consumer.programs.herdr.package} config check > "$out"
  '';
  herdr-settings-modes-regression =
    assert !(lib.hasAttr "herdr/config.toml" empty.xdg.configFile);
    assert lib.hasAttr "herdr/config.toml" configured.xdg.configFile;
    assert builtins.deepSeq "${configured.xdg.configFile."herdr/config.toml".source}" true;
    helpers.mkMarker "check-herdr-settings-modes-regression" "Herdr config.toml is linked when settings are configured.";
}
