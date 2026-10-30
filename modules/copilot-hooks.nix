{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.copilot-cli;
  json = pkgs.formats.json { };
in
{
  options.programs.copilot-cli = {
    enable = lib.mkEnableOption "GitHub Copilot CLI configuration";
    nativeHooks = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "Copilot hook events rendered into settings.json.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.nativeHooks != { }) {
    home.file.".copilot/settings.json".source = json.generate "copilot-settings.json" {
      hooks = cfg.nativeHooks;
    };
  };
}
