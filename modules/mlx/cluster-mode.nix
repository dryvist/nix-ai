#
# MLX Module — Clustered Mode (two-Mac JACCL distributed serving)
#
# In clustered mode, one Thunderbolt 5 cable turns two Macs into a single MLX
# pipeline-parallel cluster serving a frontier-class model that neither
# machine can hold alone. Each host runs its own rank from launchd (no SSH
# orchestration): a link watcher detects the cable, quiesces normal serving,
# and starts the rank; unplugging reverses it unattended.
#
# Serving stack is first-party mlx-lm: `mlx_lm.server` on every rank — rank 0
# (coordinator) binds the OpenAI-compatible HTTP endpoint, all ranks
# participate in generation. Distributed init is driven by the documented
# environment contract (MLX_RANK / MLX_JACCL_COORDINATOR / MLX_IBV_DEVICES).
# Sharding mode is per-model (`shardingMode`): tensor parallelism is mlx-lm's
# default and what almost every architecture implements, so --pipeline is
# opt-in, not a constant.
#
# The env contract is DECLARATIVE except the one value that names a physical
# port. The rendezvous address is the coordinator's static link IPv4 (JACCL's
# parser is IPv4-only: every IPv6 form, including [::1]:port, failed with
# "Can't parse address" — validated 2026-07-11), which nix-darwin's
# cluster-link prep pins on every Thunderbolt port at activation. The ibv
# device matrix is written at rank start by ./scripts/cluster-rank-launch.sh
# from the locally-discovered Thunderbolt device, so moving the cable to
# another port no longer wedges the mesh; `rdmaDevice` remains the override
# for when discovery is wrong. RDMA prerequisite: `rdma_ctl enable` on BOTH
# Macs (done 2026-07-16).
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
    modelServerProcessPattern
    ;
  ncfg = cfg.clusterMode;
  versions = import ../../lib/versions.nix;

  rankLabel = "dev.mlx-cluster.rank";
  watcherLabel = "dev.mlx-cluster.watcher";
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  stateFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/link-state";
  # Written by the rank launcher at start (not a nix-managed file — its content
  # depends on which physical Thunderbolt port has the cable).
  ibvMatrixFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/ibv-matrix.json";
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
    "--host"
    "127.0.0.1"
    "--port"
    (toString ncfg.httpPort)
  ]
  # Tensor parallelism is the mlx-lm default and emits no flag; --pipeline opts
  # OUT of it and only glm4_moe/glm4_moe_lite implement it (see shardingMode).
  # The two mlx_lm predicates, verbatim:
  #   has_pipelining      = hasattr(model, "model") and hasattr(model.model, "pipeline")
  #   has_tensor_parallel = hasattr(model, "shard")
  ++ lib.optional (ncfg.shardingMode == "pipeline") "--pipeline"
  ++ ncfg.extraServerArgs;

  # Thin wrapper in front of the rank: discovers the RDMA device, writes the
  # ibv matrix, execs clusterRankArgs. Everything else stays baked at eval.
  clusterRankLaunchPkg = pkgs.writeShellApplication {
    name = "mlx-cluster-rank-launch";
    text = builtins.readFile ./scripts/cluster-rank-launch.sh;
  };

  clusterWatcherPkg = pkgs.writeShellApplication {
    name = "mlx-cluster-link-watcher";
    runtimeInputs = [ pkgs.curl ];
    # Helpers first, then the state machine (split for the per-file size cap).
    # Concatenation, not sourcing: the helper bodies read `uid` and the
    # CLUSTER_* env from the watcher's own scope, resolved at call time.
    text = lib.concatStrings [
      (builtins.readFile ./scripts/cluster-link-helpers.sh)
      (builtins.readFile ./scripts/cluster-link-watcher.sh)
    ];
  };

  # Lifecycle-command builder lives in ./cluster-cli-builder.nix (split out for
  # the per-file size cap, same as ./cluster-cli-env.nix below).
  mkClusterCli = import ./cluster-cli-builder.nix { inherit lib pkgs; };

  # Lifecycle-command env contract lives in ./cluster-cli-env.nix (split out
  # for the per-file size cap); the packages that consume it stay here.
  clusterCliEnv = import ./cluster-cli-env.nix {
    inherit
      lib
      ncfg
      cfg
      isCoordinator
      staticSelfIp
      staticPeerIp
      rankLabel
      watcherLabel
      launchAgentsDir
      launchAgentLabel
      warmupAgentLabel
      stateFile
      apiUrl
      modelServerProcessPattern
      ;
  };

  clusterJoinPkg = mkClusterCli "cluster-join" ./scripts/cluster-join.sh clusterCliEnv.clusterJoinEnv;
  clusterDetachPkg =
    mkClusterCli "cluster-detach" ./scripts/cluster-detach.sh
      clusterCliEnv.clusterDetachEnv;
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

    launchd.agents = {
      # The rank itself. Started/stopped exclusively by the link watcher —
      # RunAtLoad=false + KeepAlive=false means an unplugged cable and
      # rebuilds leave it idle. Interactive QoS: Background clamps Metal
      # decode throughput (same lesson as the normal-mode server agent).
      mlx-cluster-rank = {
        enable = true;
        config = {
          Label = rankLabel;
          ProgramArguments = [ (lib.getExe clusterRankLaunchPkg) ] ++ clusterRankArgs;
          RunAtLoad = false;
          KeepAlive = false;
          ThrottleInterval = 60;
          ProcessType = "Interactive";
          AbandonProcessGroup = false;
          EnvironmentVariables = {
            HF_HOME = cfg.huggingFaceHome;
            MLX_RANK = if isCoordinator then "0" else "1";
            MLX_JACCL_COORDINATOR = "${ncfg.staticLinkIps.coordinator}:${toString ncfg.rendezvousPort}";
            # The launcher rewrites this file from the discovered device and
            # re-exports the variable; setting it here keeps the contract
            # visible and gives mlx a valid path if the launcher is bypassed.
            MLX_IBV_DEVICES = ibvMatrixFile;
            CLUSTER_IBV_MATRIX_FILE = ibvMatrixFile;
            CLUSTER_RDMA_DEVICE = ncfg.rdmaDevice;
          }
          // lib.optionalAttrs ncfg.fastMetalSync {
            # Faster GPU/CPU synchronization for distributed decode — and the
            # reason a GPU failure hangs instead of raising (see fastMetalSync).
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
            CLUSTER_MAX_WARM_FAILURES = toString ncfg.maxWarmFailures;
            # The link-down re-warm POSTs through llama-swap, so the watcher
            # needs to be able to bootstrap that agent when cluster-join has
            # booted it out -- otherwise the kickstart silently no-ops and
            # standalone serving never returns (INC-17071). Same pair
            # cluster-detach already carries, so both paths converge.
            CLUSTER_SERVER_LABEL = launchAgentLabel;
            CLUSTER_SERVER_PLIST = "${launchAgentsDir}/${launchAgentLabel}.plist";
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
