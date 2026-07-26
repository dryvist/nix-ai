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
  # Cluster override if set, else the module-wide convention
  # (./options-launch.nix). Resolved once, here, so both agents
  # cannot disagree about how they are launched.
  appleInterp = if ncfg.appleInterpreter != null then ncfg.appleInterpreter else cfg.appleInterpreter;
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
    # jq: the Slack alert payload is JSON-encoded, never string-interpolated.
    # coreutils: `timeout` bounds both the rendezvous probe and the activation
    # repair pass, and macOS ships no timeout(1).
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    # Function definitions first, then the state machine (split for the per-file
    # size cap). Concatenation, not sourcing: the helper bodies read `uid` and
    # the CLUSTER_* env from the watcher's own scope, resolved at call time.
    text = lib.concatStrings [
      (builtins.readFile ./scripts/cluster-link-helpers.sh)
      (builtins.readFile ./scripts/cluster-link-locate.sh)
      (builtins.readFile ./scripts/cluster-link-repair.sh)
      (builtins.readFile ./scripts/cluster-link-guards.sh)
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

  # Both lifecycle commands consume the shared link-prep primitives (each used to
  # carry its own copy of iface_holding_self_ip), so each is built from the layers
  # it uses plus its own body. Each gets EXACTLY the layers it calls:
  # writeShellApplication runs shellcheck at default severity, so shipping a
  # function a consumer never invokes fails the build (SC2329) — which is a
  # useful pressure toward finely-split libraries, not an inconvenience.
  clusterJoinPkg = mkClusterCli "cluster-join" [
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-link-repair.sh
    ./scripts/cluster-join.sh
  ] clusterCliEnv.clusterJoinEnv;
  clusterDetachPkg = mkClusterCli "cluster-detach" [
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-detach.sh
  ] clusterCliEnv.clusterDetachEnv;

  # Watcher env contract lives in ./cluster-watcher-env.nix (split out for the
  # per-file size cap, same as ./cluster-cli-env.nix); it also derives the
  # link-down settle window into probe strikes.
  clusterWatcherEnv = import ./cluster-watcher-env.nix {
    inherit
      lib
      ncfg
      cfg
      isCoordinator
      staticSelfIp
      staticPeerIp
      rankLabel
      warmupAgentLabel
      launchAgentLabel
      launchAgentsDir
      stateFile
      ;
  };
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
      {
        assertion = ncfg.rankStartAlignMultiple >= 2;
        message = "programs.mlx.clusterMode: rankStartAlignMultiple must be >= 2. The shared rank-start boundary only aligns two hosts when its period EXCEEDS the watcher tick; at exactly one tick, hosts whose ticks fall either side of a boundary map to different boundaries and the cluster never forms.";
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
          # Launched through Apple's interpreter, not the script's Nix shebang,
          # so the whole chain is Apple-signed and macOS grants it Local Network
          # unconditionally. See programs.mlx.appleInterpreter for why a Nix
          # shebang here made the cluster unable to self-form.
          ProgramArguments = lib.optional (appleInterp != null) appleInterp ++ [
            (lib.getExe clusterWatcherPkg)
          ];
          RunAtLoad = true;
          # The convergence quantum. Every seconds-valued watcher threshold is
          # converted into ticks against this one number (see
          # ./cluster-watcher-env.nix), so none of them can drift from it.
          StartInterval = ncfg.tickIntervalSecs;
          ProcessType = "Background";
          EnvironmentVariables = clusterWatcherEnv;
          StandardOutPath = "${logDir}/cluster-watcher.log";
          StandardErrorPath = "${logDir}/cluster-watcher.error.log";
        };
      };
    };
    # Prefetch + log rotation live in ./cluster-mode-maintenance.nix.
  };
}
