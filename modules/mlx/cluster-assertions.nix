#
# MLX Module — clustered-mode assertions
#
# Split out of ./cluster-mode.nix at the per-file byte cap (.file-size.yml).
# Each entry states an invariant that would otherwise fail at runtime in a way
# that is hard to attribute, so it is asserted at eval instead.
#
{ ncfg, cfg }:
[
  {
    assertion = ncfg.httpPort != cfg.port && ncfg.rendezvousPort != cfg.port;
    message = "programs.mlx.clusterMode: cluster ports must not clash with the normal-mode proxy port.";
  }
  {
    assertion = ncfg.httpPort != ncfg.rendezvousPort;
    message = "programs.mlx.clusterMode: httpPort and rendezvousPort must differ or the service cannot bind.";
  }
  {
    # The shared rank-start boundary only aligns two hosts when its period
    # EXCEEDS the watcher tick. At exactly one tick, hosts whose ticks fall
    # either side of a boundary map to DIFFERENT boundaries and never overlap,
    # so the cluster never forms — the failure this boundary exists to prevent.
    assertion = ncfg.rankStartAlignMultiple >= 2;
    message = "programs.mlx.clusterMode: rankStartAlignMultiple must be >= 2, or the rank-start boundary period equals the watcher tick and the two hosts can align to different boundaries forever.";
  }
  {
    # A node that can be QUIESCED must be able to be RESTORED, and the config is
    # the only place that can guarantee it. Without this, a worker with a quiesce
    # hook and no restore hook boots its serving agents out on every join and has
    # no way to bring them back: the watcher's up->down edge, the PD-guard halt,
    # the wedge teardown and cluster-detach all call restore_normal_serving,
    # which on a worker is nothing but this command. That asymmetry shipped, and
    # on 2026-08-01 it left a host serving connection-refused for 86 hours while
    # every teardown path reported success.
    assertion =
      ncfg.role == "coordinator" || ncfg.quiesceCommand == null || ncfg.restoreCommand != null;
    message = "programs.mlx.clusterMode: a worker with quiesceCommand set must also set restoreCommand, or nothing can bring standalone serving back after a join.";
  }
]
