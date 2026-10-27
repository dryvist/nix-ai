#
# MLX Module — clustered-mode schedule options (nightly join, daytime detach)
#
# Split out of ./options-cluster.nix like ./options-cluster-lifecycle.nix, to keep
# each file under the repo per-file size cap. Option paths are under
# programs.mlx.clusterMode.schedule. The agents are in ./cluster-schedule.nix.
#
# Off by default. The times are launchd StartCalendarInterval keys in local time.
# The night window runs from nightStart to dayStart. It wraps midnight when it
# starts later than it ends.
#
{ lib, ... }:
let
  timeOfDay = lib.types.submodule {
    options = {
      Hour = lib.mkOption {
        type = lib.types.ints.between 0 23;
        description = "Hour of day, 0-23, in local time.";
      };
      Minute = lib.mkOption {
        type = lib.types.ints.between 0 59;
        default = 0;
        description = "Minute of the hour, 0-59.";
      };
    };
  };
in
{
  options.programs.mlx.clusterMode.schedule = {
    enable = lib.mkEnableOption "the nightly cluster join and daytime detach launchd agents (coordinator only)";

    nightStart = lib.mkOption {
      type = timeOfDay;
      default = {
        Hour = 23;
        Minute = 0;
      };
      description = "Local time the nightly agent fires. It runs the read-only preflight, then the existing join on a pass.";
    };

    dayStart = lib.mkOption {
      type = timeOfDay;
      default = {
        Hour = 7;
        Minute = 0;
      };
      description = "Local time the daytime agent fires. It runs the existing detach when this host is clustered.";
    };

    swapThresholdMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8000;
      description = "The nightly preflight holds when vm.swapusage used exceeds this many MiB.";
    };
  };
}
