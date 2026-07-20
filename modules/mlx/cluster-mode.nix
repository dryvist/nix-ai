#
# MLX Module — Clustered Mode (two-Mac JACCL distributed serving)
#
# In clustered mode, one Thunderbolt 5 cable turns two Macs into a single MLX
# pipeline-parallel cluster serving a frontier-class model that neither
# machine can hold alone. Each host runs its own rank from launchd (no SSH
# orchestration): a link watcher detects the cable, quiesces normal serving,
# and starts the rank; unplugging reverses it unattended.
#
# Serving stack is first-party mlx-lm: `mlx_lm.server --pipeline` on every
# rank — rank 0 (coordinator) binds the OpenAI-compatible HTTP endpoint,
# all ranks participate in generation. Distributed init is driven by the
# documented environment contract (MLX_RANK / MLX_JACCL_COORDINATOR /
# MLX_IBV_DEVICES). --pipeline is required: the pinned mlx-lm release ships
# PipelineMixin for glm4_moe but not tensor-parallel shard().
#
# The whole env contract is DECLARATIVE — no runtime discovery, no launcher
# script. The rendezvous address is the coordinator's static link IPv4
# (JACCL's parser is IPv4-only: every IPv6 form, including [::1]:port, failed
# with "Can't parse address" — validated 2026-07-11), which nix-darwin's
# cluster-link prep pins on every Thunderbolt port at activation. The ibv
# device matrix is a nix-generated file keyed by `rdmaDevice`; correct it
# once from `ibv_devices` output if the default does not match. RDMA
# prerequisite: `rdma_ctl enable` on BOTH Macs (done 2026-07-16).
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared)
    cfg
    warmupAgentLabel
    launchAgentLabel
    apiUrl
    uvPythonVersion
    ;
  ncfg = cfg.clusterMode;
  versions = import ../../lib/versions.nix;

  rankLabel = "dev.mlx-cluster.rank";
  watcherLabel = "dev.mlx-cluster.watcher";
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  stateFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/link-state";
  ibvMatrixFile = "${config.home.homeDirectory}/.config/mlx-cluster/ibv-matrix.json";
  launchAgentsDir = "${config.home.homeDirectory}/Library/LaunchAgents";

  isCoordinator = ncfg.role == "coordinator";
  staticPeerIp = if isCoordinator then ncfg.staticLinkIps.worker else ncfg.staticLinkIps.coordinator;
  staticSelfIp = if isCoordinator then ncfg.staticLinkIps.coordinator else ncfg.staticLinkIps.worker;

  clusterRankArgs = [
    "${pkgs.uv}/bin/uvx"
    # Pin the CPython minor so the coordinator and worker ranks resolve the same
    # mlx ABI (single-source uvPythonVersion; see modules/mlx/default.nix).
    "--python"
    uvPythonVersion
    "--from"
    "mlx-lm==${versions.mlxLm}"
    # mlx + mlx-lm are a lockstep pair (lib/versions.nix): pin mlx explicitly
    # like the normal-mode stack does, instead of riding mlx-lm's transitive
    # floor — otherwise the two ranks can resolve an mlx never validated here.
    "--with"
    "mlx==${versions.mlx}"
    "--with"
    "transformers==${versions.transformers}"
    "mlx_lm.server"
    "--model"
    ncfg.model
    "--pipeline"
    "--host"
    "127.0.0.1"
    "--port"
    (toString ncfg.httpPort)
  ]
  ++ ncfg.extraServerArgs;

  clusterWatcherPkg = pkgs.writeShellApplication {
    name = "mlx-cluster-link-watcher";
    runtimeInputs = [ pkgs.curl ];
    text = builtins.readFile ./scripts/cluster-link-watcher.sh;
  };

  # Lifecycle commands (cluster-join / cluster-detach): supervised, verifiable
  # front-ends over the watcher's already-designed teardown/bring-up. The whole
  # CLUSTER_* env contract is baked at eval (mirrors the watcher agent) so the
  # commands need no shell environment and behave identically on both nodes.
  # System binaries (launchctl, ifconfig, ping, sysctl, sudo, pgrep) are called
  # by absolute path — only curl/jq/coreutils ride the sanitized PATH.
  mkClusterCli =
    name: scriptFile: env:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        curl
        jq
        coreutils
        git # generation-parity preflight (ls-remote)
      ];
      text = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") env
        ++ [ (builtins.readFile scriptFile) ]
      );
    };

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

  clusterJoinPkg = mkClusterCli "cluster-join" ./scripts/cluster-join.sh clusterJoinEnv;
  clusterDetachPkg = mkClusterCli "cluster-detach" ./scripts/cluster-detach.sh clusterDetachEnv;
in
{
  # Clustered-mode option DECLARATIONS live in ./options-cluster.nix (split out
  # for the per-file size cap; option paths are unchanged — the module system
  # merges them with the staticLinkIps option below and the config block).
  # staticLinkIps stays here so the synthetic point-to-point link defaults sit
  # beside the config that consumes them.
  options.programs.mlx.clusterMode = {
    staticLinkIps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # Synthetic point-to-point net for the Thunderbolt cable itself —
        # module-defined defaults, not site topology. Must match the
        # nix-darwin clusterLinkPrep.linkIps defaults; override only on
        # subnet clash.
        coordinator = "192.168.208.1";
        worker = "192.168.208.2";
      };
      description = "Link addresses of the two cable ends (pinned on the Thunderbolt ports by nix-darwin at activation).";
    };
  };

  config = lib.mkIf (cfg.enable && ncfg.enable) {
    assertions = [
      {
        assertion = ncfg.httpPort != cfg.port && ncfg.rendezvousPort != cfg.port;
        message = "programs.mlx.clusterMode: cluster ports must not clash with the normal-mode proxy port.";
      }
      {
        assertion = ncfg.httpPort != ncfg.rendezvousPort;
        message = "programs.mlx.clusterMode: httpPort and rendezvousPort must differ or the service cannot bind.";
      }
    ];

    # Lifecycle commands on PATH on both nodes (one-click cluster bring-up /
    # safe-unplug over the watcher). Shipped only when clusterMode is enabled.
    home.packages = [
      clusterJoinPkg
      clusterDetachPkg
    ];

    # Symmetric 2-rank ibv matrix, generated at eval — no runtime discovery.
    home.file.".config/mlx-cluster/ibv-matrix.json".text = ''
      [[null, "${ncfg.rdmaDevice}"], ["${ncfg.rdmaDevice}", null]]
    '';

    launchd.agents = {
      # The rank itself. Started/stopped exclusively by the link watcher —
      # RunAtLoad=false + KeepAlive=false means an unplugged cable and
      # rebuilds leave it idle. Interactive QoS: Background clamps Metal
      # decode throughput (same lesson as the normal-mode server agent).
      mlx-cluster-rank = {
        enable = true;
        config = {
          Label = rankLabel;
          ProgramArguments = clusterRankArgs;
          RunAtLoad = false;
          KeepAlive = false;
          ThrottleInterval = 60;
          ProcessType = "Interactive";
          AbandonProcessGroup = false;
          EnvironmentVariables = {
            HF_HOME = cfg.huggingFaceHome;
            MLX_RANK = if isCoordinator then "0" else "1";
            MLX_JACCL_COORDINATOR = "${ncfg.staticLinkIps.coordinator}:${toString ncfg.rendezvousPort}";
            MLX_IBV_DEVICES = ibvMatrixFile;
            # Faster GPU/CPU synchronization for distributed decode.
            MLX_METAL_FAST_SYNCH = "1";
          };
          StandardOutPath = "${logDir}/cluster-rank.log";
          StandardErrorPath = "${logDir}/cluster-rank.error.log";
        };
      };

      # Link watcher: one state-machine tick per interval (see the script for
      # the transition table).
      mlx-cluster-watcher = {
        enable = true;
        config = {
          Label = watcherLabel;
          ProgramArguments = [ (lib.getExe clusterWatcherPkg) ];
          RunAtLoad = true;
          StartInterval = 30;
          ProcessType = "Background";
          EnvironmentVariables = {
            CLUSTER_ROLE = ncfg.role;
            CLUSTER_RANK_LABEL = rankLabel;
            CLUSTER_WARMUP_LABEL = warmupAgentLabel;
            CLUSTER_NORMAL_PROXY = "http://127.0.0.1:${toString cfg.port}";
            CLUSTER_STATE_FILE = stateFile;
            CLUSTER_MAX_KICKSTARTS = toString ncfg.maxKickstarts;
            CLUSTER_ALERT_URL_FILE = ncfg.alertUrlFile;
            CLUSTER_STATIC_PEER_IP = staticPeerIp;
          }
          // lib.optionalAttrs isCoordinator {
            # Readiness probe target: launchctl liveness alone cannot see a
            # rank hung in distributed init (see the watcher script). Only rank
            # 0 binds the endpoint, so the coordinator also carries the URL and
            # model for the post-readiness first-token warm-up.
            CLUSTER_HTTP_PORT = toString ncfg.httpPort;
            CLUSTER_RANK_URL = "http://127.0.0.1:${toString ncfg.httpPort}";
            CLUSTER_MODEL = ncfg.model;
          }
          // lib.optionalAttrs (ncfg.wiredLimitMb != null) {
            CLUSTER_WIRED_LIMIT_MB = toString ncfg.wiredLimitMb;
            CLUSTER_STANDALONE_WIRED_LIMIT_MB = toString ncfg.standaloneWiredLimitMb;
          }
          // lib.optionalAttrs (ncfg.quiesceCommand != null) {
            CLUSTER_QUIESCE_CMD = ncfg.quiesceCommand;
          }
          // lib.optionalAttrs (ncfg.restoreCommand != null) {
            CLUSTER_RESTORE_CMD = ncfg.restoreCommand;
          };
          StandardOutPath = "${logDir}/cluster-watcher.log";
          StandardErrorPath = "${logDir}/cluster-watcher.error.log";
        };
      };
    };
    # Prefetch + log rotation live in ./cluster-mode-maintenance.nix.
  };
}
