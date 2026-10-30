{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.opencode;
  json = pkgs.formats.json { };
in
{
  options.programs.opencode = {
    tuiSettings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "OpenCode V1 TUI settings, including composable plugin registrations.";
    };
    cliSettings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "OpenCode V2 CLI settings, including composable plugin registrations.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge [
      (lib.mkIf (cfg.tuiSettings != { }) {
        "${cfg.configDir}/tui.jsonc".source = json.generate "opencode-tui.jsonc" cfg.tuiSettings;
      })
      (lib.mkIf (cfg.cliSettings != { }) {
        "${cfg.configDir}/cli.json".source = json.generate "opencode-cli.json" cfg.cliSettings;
      })
    ];
  };
}
