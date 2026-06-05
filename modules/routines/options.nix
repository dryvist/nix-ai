# Routines Options
#
# Generic scheduled task options for running AI CLI commands via launchd.
# Each task has a prompt, AI tool selection, schedule, and working directory.
# Implementation in ./default.nix
{ lib, ... }:

{
  options.programs.routines = {
    enable = lib.mkEnableOption "Scheduled AI routines via launchd";

    logDir = lib.mkOption {
      type = lib.types.str;
      default = ".routines/logs";
      description = "Log directory relative to home directory";
    };

    promptsDir = lib.mkOption {
      type = lib.types.str;
      default = ".routines/prompts";
      description = "Prompt files directory relative to home directory";
    };

    tasks = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            prompt = lib.mkOption {
              type = lib.types.str;
              description = "Prompt text to pass to the AI CLI";
            };

            aiTool = lib.mkOption {
              type = lib.types.enum [
                "antigravity-cli"
                "claude"
              ];
              default = "antigravity-cli";
              description = "AI CLI to use for this task";
            };

            model = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Optional model override passed to the AI CLI via --model.
                Leave null (default) so the CLI picks its current best model —
                avoids stale pins as upstream defaults move forward.
              '';
            };

            schedule = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  times = lib.mkOption {
                    type = lib.types.listOf (
                      lib.types.submodule {
                        options = {
                          hour = lib.mkOption {
                            type = lib.types.ints.between 0 23;
                            description = "Hour of day (0-23)";
                          };
                          minute = lib.mkOption {
                            type = lib.types.ints.between 0 59;
                            default = 0;
                            description = "Minute of hour (0-59)";
                          };
                        };
                      }
                    );
                    default = [ ];
                    description = ''
                      List of times to run each day.
                      Example:
                        times = [{ hour = 6; minute = 13; }];
                    '';
                  };
                };
              };
              description = "When to run the task";
            };

            workingDirectory = lib.mkOption {
              type = lib.types.str;
              description = "Working directory for the launchd agent (absolute path)";
            };

            enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this task's schedule is active";
            };
          };
        }
      );
      default = { };
      description = "Scheduled AI routine tasks";
    };
  };
}
