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
    watchdogAgentLabel
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
  # Ledger of RDMA protection domains leaked during the current boot: written by
  # cluster-detach when it must SIGKILL, read by the watcher's start guard and by
  # cluster-join. Defined ONCE, here — a writer and a reader that each derive the
  # path are a writer and a reader on different files. Boot-scoped: only a
  # reboot clears it (see cluster-pd-ledger.sh for why).
  pdDebtFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/pd-debt";
  # Written by the rank launcher at start (not a nix-managed file — its content
  # depends on which physical Thunderbolt port has the cable).
  ibvMatrixFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/ibv-matrix.json";
  launchAgentsDir = "${config.home.homeDirectory}/Library/LaunchAgents";
  rankErrorLog = "${logDir}/cluster-rank.error.log";

  isCoordinator = ncfg.role == "coordinator";
  staticPeerIp = if isCoordinator then ncfg.staticLinkIps.worker else ncfg.staticLinkIps.coordinator;
  staticSelfIp = if isCoordinator then ncfg.staticLinkIps.coordinator else ncfg.staticLinkIps.worker;

  # Rank server argv lives in ./cluster-rank-args.nix (split out for the
  # per-file byte cap), same pattern as ./cluster-cli-env.nix below.
  clusterRankArgs = import ./cluster-rank-args.nix {
    inherit
      lib
      pkgs
      ncfg
      uvPythonVersion
      versions
      ;
  };

  # Which shell layers each cluster script is assembled from, and why each
  # consumer gets exactly the layers it calls (shellcheck SC2329 enforces it).
  # Shared with ./peer-liveness.nix so there is one place that answers "what is
  # this script made of".
  scriptLayers = import ./cluster-script-layers.nix;

  # Thin wrapper in front of the rank: discovers the RDMA device, writes the
  # ibv matrix, execs clusterRankArgs. Everything else stays baked at eval.
  clusterRankLaunchPkg = pkgs.writeShellApplication {
    name = "mlx-cluster-rank-launch";
    text = builtins.readFile ./scripts/cluster-rank-launch.sh;
  };

  clusterWatcherPkg = pkgs.writeShellApplication {
    name = "mlx-cluster-link-watcher";
    # jq: the Slack alert payload is JSON-encoded, never string-interpolated.
    # coreutils: `timeout` bounds the rendezvous probe, the activation repair
    # pass and the parity ls-remote, and macOS ships no timeout(1).
    # git: the periodic generation-parity check reads the deploy branch HEAD with
    # `ls-remote` — the drift that disarmed link prep for 86 hours was invisible
    # because nothing on a timer ever asked.
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.git
    ];
    # Function definitions first, then the state machine. Concatenation, not
    # sourcing: the helper bodies read `uid` and the CLUSTER_* env from the
    # watcher's own scope, resolved at call time. The layer list — and why each
    # consumer gets exactly the layers it calls — lives in
    # ./cluster-script-layers.nix.
    text = lib.concatStrings (map builtins.readFile scriptLayers.watcher);
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
      watchdogAgentLabel
      stateFile
      pdDebtFile
      apiUrl
      modelServerProcessPattern
      rankErrorLog
      ;
  };

  # Both lifecycle commands consume the shared link-prep primitives (each used to
  # carry its own copy of iface_holding_self_ip), so each is built from the layers
  # it uses plus its own body. Those layer sets, and the privilege boundary they
  # encode between the PD ledger's read and write sides, live in
  # ./cluster-script-layers.nix.
  clusterJoinPkg = mkClusterCli "cluster-join" scriptLayers.join clusterCliEnv.clusterJoinEnv;
  clusterDetachPkg = mkClusterCli "cluster-detach" scriptLayers.detach clusterCliEnv.clusterDetachEnv;

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
      watchdogAgentLabel
      launchAgentsDir
      stateFile
      pdDebtFile
      rankErrorLog
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
    # Invariants live in ./cluster-assertions.nix (split out for the byte cap).
    assertions = import ./cluster-assertions.nix { inherit ncfg cfg; };

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
          # Apple's interpreter, like the watcher and peer-liveness agents
          # beside it: a Nix binary's signing identity is its content hash, so
          # a Local Network grant dies on the next rebuild. Worst here — the
          # rank alone opens the jaccl rendezvous, and each denied start burns
          # a boot-scoped protection domain. See programs.mlx.appleInterpreter.
          ProgramArguments =
            lib.optional (appleInterp != null) appleInterp
            ++ [ (lib.getExe clusterRankLaunchPkg) ]
            ++ clusterRankArgs;
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
          StandardErrorPath = rankErrorLog;
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
