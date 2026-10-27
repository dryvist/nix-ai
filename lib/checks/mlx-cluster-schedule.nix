# Eval-time proof of the schedule agents (modules/mlx/cluster-schedule.nix). Both
# agents are absent while schedule.enable is false. When it is true, both exist on
# the coordinator and neither exists on the worker. The evaluations come from
# ../checks-fixtures-cluster-schedule.nix.
{
  pkgs,
  hmConfigCluster,
  hmConfigClusterScheduled,
  hmConfigClusterScheduledWorker,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  nightly = "mlx-cluster-schedule-nightly";
  daytime = "mlx-cluster-schedule-daytime";
  agentsOf = hm: hm.config.launchd.agents;
  hasAgent = hm: name: builtins.hasAttr name (agentsOf hm);
in
{
  mlx-cluster-schedule-agents =
    assert
      !(hasAgent hmConfigCluster nightly) && !(hasAgent hmConfigCluster daytime)
      || throw "cluster schedule: both agents must be absent while programs.mlx.clusterMode.schedule.enable is false";
    assert
      hasAgent hmConfigClusterScheduled nightly && hasAgent hmConfigClusterScheduled daytime
      || throw "cluster schedule: a coordinator with schedule.enable must define both agents";
    assert
      !(hasAgent hmConfigClusterScheduledWorker nightly)
      && !(hasAgent hmConfigClusterScheduledWorker daytime)
      || throw "cluster schedule: the worker role must define neither schedule agent";
    assert
      (agentsOf hmConfigClusterScheduled).${nightly}.config.Label == "dev.mlx-cluster.schedule-nightly"
      || throw "cluster schedule: the nightly agent label must be dev.mlx-cluster.schedule-nightly";
    helpers.mkMarker "check-mlx-cluster-schedule-agents" "schedule agents are absent while disabled, and coordinator-only when enabled";
}
