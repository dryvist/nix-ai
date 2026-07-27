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
]
