#
# MLX Module — clustered-mode schedule agents (default off)
#
# Two launchd agents turn the manual cluster-join and cluster-detach pair into a
# nightly join and a daytime detach, with no AI step in the loop. Both run on the
# coordinator only, and only when programs.mlx.clusterMode.schedule.enable is set.
# Otherwise the attribute set is empty and no agent is defined.
#
#   dev.mlx-cluster.schedule-nightly  read-only preflight, then the existing join on a pass
#   dev.mlx-cluster.schedule-daytime  the existing detach, when this host is clustered
#
# Neither agent reboots or retries. A lifecycle exit 3 is logged and propagated,
# so launchd records it and an operator acts.
#
# Split out of ./cluster-mode.nix for the per-file size cap. The lifecycle packages
# it launches are built there from the same env contract, and passed in.
#
{
  lib,
  config,
  mlxShared,
  mkClusterCli,
  scriptLayers,
  clusterCliEnv,
  clusterJoinPkg,
  clusterDetachPkg,
}:
let
  inherit (mlxShared) cfg;
  ncfg = cfg.clusterMode;
  scfg = ncfg.schedule;
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  minuteOfDay = time: time.Hour * 60 + time.Minute;
  scheduleEnv = {
    CLUSTER_SCHEDULE_NIGHT_START_MIN = toString (minuteOfDay scfg.nightStart);
    CLUSTER_SCHEDULE_DAY_START_MIN = toString (minuteOfDay scfg.dayStart);
    CLUSTER_SCHEDULE_SWAP_THRESHOLD_MB = toString scfg.swapThresholdMiB;
  };
  preflightPkg = mkClusterCli "cluster-schedule-preflight" scriptLayers.schedulePreflight (
    clusterCliEnv.clusterJoinEnv // scheduleEnv
  );
  nightlyPkg = mkClusterCli "cluster-schedule-nightly" scriptLayers.scheduleNightly {
    CLUSTER_SCHEDULE_PREFLIGHT_BIN = lib.getExe preflightPkg;
    CLUSTER_JOIN_BIN = lib.getExe clusterJoinPkg;
  };
  daytimePkg = mkClusterCli "cluster-schedule-daytime" scriptLayers.scheduleDaytime (
    clusterCliEnv.clusterDetachEnv // { CLUSTER_DETACH_BIN = lib.getExe clusterDetachPkg; }
  );
  # Same launch convention as the rank and peer-state agents: the join reaches the
  # peer over the cluster link, so a configured Apple interpreter fronts it to hold
  # the Local Network grant (programs.mlx.appleInterpreter).
  appleInterp = if ncfg.appleInterpreter != null then ncfg.appleInterpreter else cfg.appleInterpreter;
  agent = name: label: pkg: time: {
    enable = true;
    config = {
      Label = label;
      ProgramArguments = lib.optional (appleInterp != null) appleInterp ++ [ (lib.getExe pkg) ];
      StartCalendarInterval = time;
      RunAtLoad = false;
      KeepAlive = false;
      # The lifecycle commands print this, so each night's log names its invoker.
      EnvironmentVariables.CLUSTER_INVOKER = label;
      StandardOutPath = "${logDir}/${name}.log";
      StandardErrorPath = "${logDir}/${name}.error.log";
    };
  };
in
lib.optionalAttrs (cfg.enable && ncfg.enable && scfg.enable && ncfg.role == "coordinator") {
  mlx-cluster-schedule-nightly =
    agent "schedule-nightly" "dev.mlx-cluster.schedule-nightly" nightlyPkg
      scfg.nightStart;
  mlx-cluster-schedule-daytime =
    agent "schedule-daytime" "dev.mlx-cluster.schedule-daytime" daytimePkg
      scfg.dayStart;
}
