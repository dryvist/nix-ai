# Maestro Auto Run Configuration Options
{
  config,
  lib,
  ...
}:

{
  options.programs.maestro = {
    enable = lib.mkEnableOption "Maestro Auto Run integration";

    appPath = lib.mkOption {
      type = lib.types.str;
      default = "/Applications/Maestro.app/Contents/MacOS/Maestro";
      description = "Path to the Maestro executable";
    };

    issueResolver = {
      enable = lib.mkEnableOption "Issue Resolver Auto Run playbook";

      schedule = {
        hour = lib.mkOption {
          type = lib.types.ints.between 0 23;
          default = 9;
          description = "Hour to run issue resolver (0-23)";
        };

        minute = lib.mkOption {
          type = lib.types.ints.between 0 59;
          default = 0;
          description = "Minute to run issue resolver (0-59)";
        };
      };

      targetRepository = lib.mkOption {
        type = lib.types.str;
        default = "${config.userConfig.paths.git}/nix-darwin/main";
        description = "Target repository for issue resolution";
      };
    };
  };
}
