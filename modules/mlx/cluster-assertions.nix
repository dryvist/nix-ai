#
# MLX Module — clustered-mode assertions
#
# Split out of ./cluster-mode.nix at the per-file byte cap (.file-size.yml).
# Each entry states an invariant that would otherwise fail at runtime in a way
# that is hard to attribute, so it is asserted at eval instead.
#
{ ncfg, cfg }:
let
  # mlx-lm's two sharding paths have DISJOINT architecture support, and naming
  # the wrong one on a pipeline-only model is SILENT rather than fatal: the
  # has_tensor_parallel predicate is simply false, so no split happens, every
  # rank loads the FULL model, and generation wedges with both ranks at the
  # wired ceiling. Nothing logs a cause, so assert it at eval instead.
  pipelineOnly = [
    "glm4_moe"
    "glm4_moe_lite"
  ];
  # THE CONVERSE LIST, AND IT FAILS THE OTHER WAY ROUND. pipelineOnly catches an
  # architecture left on the tensor-parallel default; this catches one named
  # "pipeline" that never implemented pipelining at all. That direction is not
  # silent — mlx-lm raises "The model does not support pipelining" — but it
  # raises it at RANK START, after the wired ceiling has been applied and a
  # protection domain spent, and the domain is returned by nothing short of a
  # reboot. Eval is the only place the check is free.
  #
  # A SUPERSET OF pipelineOnly BY CONSTRUCTION, never a second hand-maintained
  # list: every pipeline-ONLY architecture is by definition pipeline-CAPABLE,
  # and two lists that could disagree would let the assertion above demand a
  # mode this one rejects. It is currently the same list — glm4_moe is the only
  # architecture the catalog declares — so it is derived rather than retyped.
  # An architecture implementing BOTH paths is appended here as
  # `pipelineOnly ++ [ "..." ]`, and belongs in neither list when mlx-lm
  # tensor-parallels it but does not pipeline it.
  pipelineCapable = pipelineOnly;
  entry =
    if ncfg.modelCatalogKey == null then { } else (import ./catalog-data.nix).${ncfg.modelCatalogKey};
  arch = entry.architecture or null;
in
[
  # THE GATE MUST NEVER BE MORE IMPATIENT THAN THE TRAFFIC IT PROTECTS. Every
  # probe below can, on failure, halt the rank and tear the cluster down — and
  # the teardown leaks the wired shard on both hosts, which only a reboot
  # returns. A probe timeout under the read timeout real clients use therefore
  # converts "a client would still be waiting" into a dual reboot. Asserted
  # rather than commented because the numbers are three separate options and
  # nothing else relates them.
  {
    assertion = ncfg.healthGateTimeoutSecs > ncfg.consumerReadTimeoutSecs;
    message = "programs.mlx.clusterMode: healthGateTimeoutSecs (${toString ncfg.healthGateTimeoutSecs}s) must exceed consumerReadTimeoutSecs (${toString ncfg.consumerReadTimeoutSecs}s). A probe that gives up before real clients do declares a busy-but-healthy pipeline dead, and the teardown that follows leaks the wired shard on both hosts.";
  }
  {
    assertion = ncfg.healthGateConcurrentTimeoutSecs >= ncfg.healthGateTimeoutSecs;
    message = "programs.mlx.clusterMode: healthGateConcurrentTimeoutSecs (${toString ncfg.healthGateConcurrentTimeoutSecs}s) must be at least healthGateTimeoutSecs (${toString ncfg.healthGateTimeoutSecs}s) — N requests competing for one rank cannot be given less time than one request alone.";
  }
  {
    assertion = (ncfg.modelCatalogKey != null) -> (arch != null);
    message = "programs.mlx.clusterMode: catalog entry \"${toString ncfg.modelCatalogKey}\" is selected as the cluster model but declares no `architecture`. Add it to modules/mlx/catalog-data.nix, mirroring that model's config.json model_type, so the sharding mode can be checked.";
  }
  {
    assertion = (builtins.elem (toString arch) pipelineOnly) -> (ncfg.shardingMode == "pipeline");
    message = "programs.mlx.clusterMode: catalog entry \"${toString ncfg.modelCatalogKey}\" is architecture \"${toString arch}\", which implements pipelining and NOT tensor parallelism, so shardingMode must be \"pipeline\" (it is \"${ncfg.shardingMode}\"). Left tensor-parallel, mlx-lm performs no split at all and every rank loads the full model.";
  }
  {
    # Gated on modelCatalogKey, not on arch alone: absent a catalog entry there
    # is no architecture to judge, and an ungated `elem ""` would reject
    # pipeline mode on every host naming its model directly.
    assertion =
      (ncfg.modelCatalogKey != null)
      -> (ncfg.shardingMode == "pipeline")
      -> (builtins.elem (toString arch) pipelineCapable);
    message = "programs.mlx.clusterMode: shardingMode is \"pipeline\" but catalog entry \"${toString ncfg.modelCatalogKey}\" declares architecture \"${toString arch}\", which mlx-lm does not pipeline. The ranks abort at start with \"The model does not support pipelining\" — after the protection domain has already been spent, and only a reboot returns it. Extend pipelineCapable here once mlx-lm implements that architecture, or name shardingMode = \"tensor\".";
  }
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
    # The staleness window must outlast the watcher's OWN slowest tick, not
    # just a couple of missed publishes. The publish happens near the top of a
    # tick; the rank-start boundary sleeps inside that same tick, up to
    # rankStartAlignMultiple ticks long. So two publishes are separated by a
    # tick plus the alignment hold plus the probes. At the old 3-against-2 the
    # window equalled the hold plus one tick with nothing over to cover the
    # probes: each host can then read the other as stale, both suppress every
    # start, and the cluster fails to form even with both hosts armed and
    # healthy.
    assertion = ncfg.peerStateStaleTicks >= ncfg.rankStartAlignMultiple + 3;
    message = "programs.mlx.clusterMode: peerStateStaleTicks must be at least rankStartAlignMultiple + 3, or a host's own rank-start alignment hold delays its next publish past the window its peer judges it by, and both hosts suppress every start while armed and healthy.";
  }
  {
    # A node that can be QUIESCED must be able to be RESTORED, and the config is
    # the only place that can guarantee it. Without this, a worker with a quiesce
    # hook and no restore hook boots its serving agents out on every join and has
    # no way to bring them back: the watcher's up->down edge, the PD-guard halt,
    # the wedge teardown and cluster-detach all call restore_normal_serving,
    # which on a worker is nothing but this command. That asymmetry leaves the
    # host serving connection-refused indefinitely, with every teardown path
    # still reporting success.
    assertion =
      ncfg.role == "coordinator" || ncfg.quiesceCommand == null || ncfg.restoreCommand != null;
    message = "programs.mlx.clusterMode: a worker with quiesceCommand set must also set restoreCommand, or nothing can bring standalone serving back after a join.";
  }
]
