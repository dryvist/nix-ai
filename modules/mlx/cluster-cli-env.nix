# Lifecycle-command environment contract (cluster-join / cluster-detach).
#
# Split out of cluster-mode.nix for the per-file size cap. The whole CLUSTER_*
# env is baked at eval so the commands need no shell environment and behave
# identically on both nodes; this file owns only the attrsets, while
# cluster-mode.nix owns the packages that consume them.
{
  lib,
  ncfg,
  cfg,
  isCoordinator,
  staticSelfIp,
  staticPeerIp,
  rankLabel,
  watcherLabel,
  launchAgentsDir,
  launchAgentLabel,
  warmupAgentLabel,
  stateFile,
  apiUrl,
  modelServerProcessPattern,
}:
let
  # Env common to both commands and both roles.
  clusterCommonEnv = {
    CLUSTER_ROLE = ncfg.role;
    CLUSTER_STATIC_SELF_IP = staticSelfIp;
    CLUSTER_STATIC_PEER_IP = staticPeerIp;
    CLUSTER_RANK_LABEL = rankLabel;
    CLUSTER_WATCHER_LABEL = watcherLabel;
    CLUSTER_WATCHER_PLIST = "${launchAgentsDir}/${watcherLabel}.plist";
    CLUSTER_STATE_FILE = stateFile;
    CLUSTER_STANDALONE_WIRED_LIMIT_MB = toString ncfg.standaloneWiredLimitMb;
  }
  // lib.optionalAttrs (ncfg.wiredLimitMb != null) {
    CLUSTER_WIRED_LIMIT_MB = toString ncfg.wiredLimitMb;
  };

  clusterJoinEnv =
    clusterCommonEnv
    // {
      CLUSTER_GENERATION_REPO = ncfg.generationRepo;
      CLUSTER_JOIN_SWAP_THRESHOLD_MB = toString ncfg.joinSwapThresholdMb;
      CLUSTER_JOIN_TIMEOUT_SECS = toString ncfg.joinTimeoutSecs;
      CLUSTER_QUIESCE_GRACE_SECS = toString ncfg.quiesceGraceSecs;
      CLUSTER_WORKER_STABLE_SECS = toString ncfg.workerStableSecs;
    }
    // lib.optionalAttrs isCoordinator {
      # join consumes the watcher's rank-warmed marker (zero completions issued
      # by join itself — INC-17070), so it needs no cluster endpoint URL/model.
      CLUSTER_NORMAL_PROXY = "http://127.0.0.1:${toString cfg.port}";
      CLUSTER_SERVER_LABEL = launchAgentLabel;
      CLUSTER_WARMUP_LABEL = warmupAgentLabel;
      CLUSTER_STANDALONE_PROCESS_PATTERN = modelServerProcessPattern;
      # Newline-separated substrings of standalone-serving engines to spare from the
      # quiesce reap (standalone keep-resident backends). Empty by default.
      CLUSTER_KEEP_RESIDENT = lib.concatStringsSep "\n" ncfg.keepResidentBackends;
    }
    // lib.optionalAttrs (!isCoordinator && ncfg.quiesceCommand != null) {
      CLUSTER_QUIESCE_CMD = ncfg.quiesceCommand;
    };

  clusterDetachEnv =
    clusterCommonEnv
    // {
      CLUSTER_DETACH_SWAP_THRESHOLD_MB = toString ncfg.detachSwapThresholdMb;
      CLUSTER_DETACH_TIMEOUT_SECS = toString ncfg.detachTimeoutSecs;
    }
    // lib.optionalAttrs isCoordinator {
      CLUSTER_SERVER_LABEL = launchAgentLabel;
      CLUSTER_SERVER_PLIST = "${launchAgentsDir}/${launchAgentLabel}.plist";
      CLUSTER_WARMUP_LABEL = warmupAgentLabel;
      CLUSTER_STANDALONE_PROBE_URL = apiUrl;
      CLUSTER_STANDALONE_PROBE_MODEL = cfg.defaultModel;
    };

in
{
  inherit clusterJoinEnv clusterDetachEnv;
}
