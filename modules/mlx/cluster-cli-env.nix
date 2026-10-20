# Environment shared by the explicit cluster lifecycle commands.
{
  config,
  lib,
  ncfg,
  cfg,
  isCoordinator,
  staticSelfIp,
  staticPeerIp,
  rankLabel,
  launchAgentsDir,
  residentAgentLabels,
  watchdogAgentLabel,
  stateFile,
  stateDir,
  clusterSoftwareJson,
  modelServerProcessPattern,
}:
let
  inherit (import ./cluster-rank-pattern.nix { inherit lib; }) clusterRankProcessPattern;
  # Detach probes this host's own resident servers: the shared front port can be another gateway.
  residentContracts = lib.attrValues cfg.staticResidentContracts;
  declaredAgentLabels = map (agent: agent.config.Label) (
    lib.attrValues (
      lib.filterAttrs (_: agent: (agent.enable or false) && (agent.config ? Label)) config.launchd.agents
    )
  );
  clusterCommonEnv = {
    CLUSTER_ROLE = ncfg.role;
    CLUSTER_STATIC_SELF_IP = staticSelfIp;
    CLUSTER_STATIC_PEER_IP = staticPeerIp;
    CLUSTER_RANK_LABEL = rankLabel;
    CLUSTER_RANK_PROCESS_PATTERN = clusterRankProcessPattern;
    CLUSTER_STATE_FILE = stateFile;
    CLUSTER_STATE_DIR = stateDir;
    CLUSTER_PEER_STATE_FILE = ncfg.peerStateFile;
    CLUSTER_PEER_STATE_PORT = toString ncfg.peerStatePort;
    CLUSTER_PEER_STATE_TIMEOUT_SECS = toString ncfg.peerStateTimeoutSecs;
    CLUSTER_PEER_SSH = ncfg.peerSsh;
    CLUSTER_SOFTWARE_JSON = clusterSoftwareJson;
    CLUSTER_LIFECYCLE_LOG = "${config.home.homeDirectory}/Library/Logs/mlx-cluster/cluster-lifecycle.log";
    CLUSTER_LAUNCHCTL_BIN = "/bin/launchctl";
    CLUSTER_SYSCTL_BIN = "/usr/sbin/sysctl";
    CLUSTER_SUDO_BIN = "/usr/bin/sudo";
    CLUSTER_SW_VERS_BIN = "/usr/bin/sw_vers";
    CLUSTER_PGREP_BIN = "/usr/bin/pgrep";
    CLUSTER_PKILL_BIN = "/usr/bin/pkill";
    CLUSTER_KILL_BIN = "/bin/kill";
    CLUSTER_PS_BIN = "/bin/ps";
    CLUSTER_GREP_BIN = "/usr/bin/grep";
    CLUSTER_SH_BIN = "/bin/sh";
    CLUSTER_IOCLASSCOUNT_BIN = "/usr/sbin/ioclasscount";
    CLUSTER_IBV_DEVINFO_BIN = "/usr/bin/ibv_devinfo";
    CLUSTER_PD_DEVICE_BUDGET = toString ncfg.devicePdBudget;
    CLUSTER_PD_RESERVE = toString ncfg.pdReserve;
    CLUSTER_MODEL = ncfg.model;
    CLUSTER_SHARDING_MODE = if ncfg.shardingMode == "pipeline" then "pipeline" else "tensor";
    CLUSTER_SHARD_MEMORY_MB = toString ncfg.shardMemoryMb;
    CLUSTER_COMPOSITOR_RESERVE_MB = toString ncfg.compositorReserveMb;
    HF_HOME = cfg.huggingFaceHome;
    CLUSTER_RDMA_DEVICE = ncfg.rdmaDevice;
    CLUSTER_JOIN_TIMEOUT_SECS = toString ncfg.joinTimeoutSecs;
    CLUSTER_DETACH_TIMEOUT_SECS = toString ncfg.detachTimeoutSecs;
    CLUSTER_QUIESCE_GRACE_SECS = toString ncfg.quiesceGraceSecs;
    CLUSTER_STANDALONE_WIRED_LIMIT_MB = toString ncfg.standaloneWiredLimitMb;
    CLUSTER_DECLARED_AGENT_LABELS = lib.concatStringsSep " " declaredAgentLabels;
    CLUSTER_SERVER_LABELS = lib.concatStringsSep " " residentAgentLabels;
    CLUSTER_LAUNCH_AGENTS_DIR = launchAgentsDir;
  }
  // lib.optionalAttrs (ncfg.wiredLimitMb != null) {
    CLUSTER_WIRED_LIMIT_MB = toString ncfg.wiredLimitMb;
  }
  // lib.optionalAttrs (isCoordinator && lib.elem watchdogAgentLabel declaredAgentLabels) {
    CLUSTER_WATCHDOG_LABEL = watchdogAgentLabel;
    CLUSTER_WATCHDOG_PLIST = "${launchAgentsDir}/${watchdogAgentLabel}.plist";
  };

  clusterJoinEnv =
    clusterCommonEnv
    // {
      CLUSTER_JOIN_SWAP_THRESHOLD_MB = toString ncfg.joinSwapThresholdMb;
      CLUSTER_WORKER_STABLE_SECS = toString ncfg.workerStableSecs;
    }
    // lib.optionalAttrs isCoordinator {
      CLUSTER_QUIESCE_APPS = lib.concatStringsSep " " ncfg.quiesce.apps;
      CLUSTER_QUIESCE_LAUNCHD = lib.concatStringsSep " " ncfg.quiesce.launchdLabels;
      CLUSTER_NORMAL_PROXY = "http://127.0.0.1:${toString cfg.port}";
      CLUSTER_STANDALONE_PROCESS_PATTERN = modelServerProcessPattern;
      CLUSTER_KEEP_RESIDENT = lib.concatStringsSep "\n" ncfg.keepResidentBackends;
      CLUSTER_HTTP_PORT = toString ncfg.httpPort;
    }
    // lib.optionalAttrs (!isCoordinator && ncfg.quiesceCommand != null) {
      CLUSTER_QUIESCE_CMD = ncfg.quiesceCommand;
    }
    // lib.optionalAttrs (!isCoordinator && ncfg.restoreCommand != null) {
      CLUSTER_RESTORE_CMD = ncfg.restoreCommand;
    };

  clusterDetachEnv =
    clusterCommonEnv
    // {
      CLUSTER_DETACH_SWAP_THRESHOLD_MB = toString ncfg.detachSwapThresholdMb;
    }
    // lib.optionalAttrs (residentContracts != [ ]) {
      CLUSTER_STANDALONE_PROBES = lib.concatMapStringsSep "\n" (
        contract:
        "${contract.launchdLabel} http://127.0.0.1:${toString contract.servicePort}/v1 ${contract.model}"
      ) residentContracts;
    }
    // lib.optionalAttrs (!isCoordinator && ncfg.restoreCommand != null) {
      CLUSTER_RESTORE_CMD = ncfg.restoreCommand;
    }
    // lib.optionalAttrs (!isCoordinator && ncfg.quiesceCommand != null) {
      CLUSTER_QUIESCE_CMD = ncfg.quiesceCommand;
    };
in
{
  inherit clusterJoinEnv clusterDetachEnv;
}
