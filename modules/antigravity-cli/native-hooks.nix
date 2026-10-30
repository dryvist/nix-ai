{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.antigravity-cli;
  json = pkgs.formats.json { };
in
{
  options.programs.antigravity-cli = {
    nativeConfigDir = lib.mkOption {
      type = lib.types.str;
      default = ".gemini/config";
      description = "Home-relative directory for native Antigravity CLI hooks.";
    };
    nativeHooks = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "Named native hook blocks rendered to Antigravity CLI hooks.json.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.nativeHooks != { }) {
    home.file."${cfg.nativeConfigDir}/hooks.json".source =
      json.generate "antigravity-cli-hooks.json" cfg.nativeHooks;
    home.sessionVariables.ANTIGRAVITY_CLI_CONFIG_DIR = "${config.home.homeDirectory}/${cfg.nativeConfigDir}";
  };
}
