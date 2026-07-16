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
# MLX_IBV_DEVICES) instead of `mlx.launch`, which keeps each host
# self-contained under launchd. --pipeline is required: the pinned mlx-lm
# release ships PipelineMixin for glm4_moe but not tensor-parallel shard().
#
# Link identity: the cabled Thunderbolt port is auto-detected at runtime —
# moving the cable needs no config edit. The JACCL link-local gate was
# VALIDATED 2026-07-11 and FAILED: the rendezvous parser is IPv4-only (every
# IPv6 form, including [::1]:port, fails with "Can't parse address"), so
# linkDiscovery defaults to "static" — role-derived synthetic IPv4 that the
# nix-darwin cluster-link-prep daemon converges onto the cabled port (it also
# detaches every RDMA-capable port from the Thunderbolt bridge). RDMA
# prerequisite: `rdma_ctl enable` on BOTH Macs; verify with `ibv_devices`.
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg warmupAgentLabel;
  ncfg = cfg.clusterMode;
  versions = import ../../lib/versions.nix;

  rankLabel = "dev.mlx-cluster.rank";
  watcherLabel = "dev.mlx-cluster.watcher";
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  stateFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/link-state";

  isCoordinator = ncfg.role == "coordinator";
  isStatic = ncfg.linkDiscovery == "static";
  staticPeerIp = if isCoordinator then ncfg.staticLinkIps.worker else ncfg.staticLinkIps.coordinator;

  # The serve invocation stays a plain args list (appended after the launcher)
  # so lib/checks/mlx-cluster.nix can assert it in pure eval; the launcher only
  # computes MLX_JACCL_COORDINATOR / MLX_IBV_DEVICES at runtime and execs it.
  clusterRankArgs = [
    "${pkgs.uv}/bin/uvx"
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
    text =
      builtins.readFile ./scripts/cluster-link-lib.sh
      + builtins.readFile ./scripts/cluster-link-watcher.sh;
  };

  clusterRankLauncherPkg = pkgs.writeShellApplication {
    name = "mlx-cluster-rank-launcher";
    text =
      builtins.readFile ./scripts/cluster-link-lib.sh
      + builtins.readFile ./scripts/cluster-rank-launcher.sh;
  };
in
{
  options.programs.mlx.clusterMode = {
    enable = lib.mkEnableOption "two-Mac JACCL clustered mode (mlx-lm pipeline-parallel serving)";

    role = lib.mkOption {
      type = lib.types.enum [
        "coordinator"
        "worker"
      ];
      description = "coordinator = rank 0, binds the cluster HTTP endpoint; worker = rank 1.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "mlx-community/GLM-4.7-4bit";
      description = ''
        HuggingFace id of the cluster model. Must use an architecture with
        distributed support in the pinned mlx-lm (glm4_moe: pipeline).
        198 GB weights split across both ranks via --pipeline.
      '';
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 11440;
      description = "Cluster endpoint port on the coordinator (loopback; exposed via the host's gateway).";
    };

    rendezvousPort = lib.mkOption {
      type = lib.types.port;
      default = 11441;
      description = "JACCL coordinator rendezvous port (MLX_JACCL_COORDINATOR).";
    };

    linkDiscovery = lib.mkOption {
      type = lib.types.enum [
        "link-local"
        "static"
      ];
      default = "static";
      description = ''
        "static" (default): role-derived synthetic IPs from staticLinkIps,
        converged onto the cabled port by the nix-darwin cluster-link-prep
        daemon. "link-local" is kept for a future mlx-lm: the JACCL gate was
        validated 2026-07-11 and REJECTED — the rendezvous parser is
        IPv4-only (even [::1]:port fails to parse), so link-local cannot
        work on the pinned release.
      '';
    };

    staticLinkIps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # Synthetic point-to-point net for the Thunderbolt cable itself —
        # module-defined defaults, not site topology. Only meaningful with
        # linkDiscovery = "static"; override only on subnet clash.
        coordinator = "192.168.208.1";
        worker = "192.168.208.2";
      };
      description = "FALLBACK (linkDiscovery = \"static\"): link addresses of the two cable ends.";
    };

    maxKickstarts = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Consecutive failed rank starts before the watcher halts kickstarts
        and pages once. Every failed distributed init leaks a kernel RDMA
        Protection Domain and exhaustion is reboot-only (ml-explore/mlx#3207),
        so an unbounded crash loop forces a reboot.
      '';
    };

    alertUrlFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/mlx-cluster/alert-url";
      description = ''
        Untracked local file holding the notification URL (ntfy-style POST
        target) for the halt page. The URL names internal topology, so it is
        seeded out-of-band and never committed. Missing file = no page.
      '';
    };

    interfaceOverride = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "en3";
      description = ''
        Cabled Thunderbolt port override. Default null = auto-detect (first
        Thunderbolt port with an active link). Set only if more than one
        Thunderbolt port is cabled and the wrong one wins.
      '';
    };

    rdmaDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        RDMA device override (see `ibv_devices`). Default null = derived at
        runtime as rdma_<detected interface>.
      '';
    };

    extraServerArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra mlx_lm.server args for the cluster rank.";
    };

    prefetch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Idempotently download the cluster model at agent load (retries until complete).";
    };

    quiesceCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Worker-side hook run at link-up before the rank starts (e.g. the cluster-quiesce allowlist sweep).";
    };

    restoreCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Worker-side hook run at link-down after the rank stops.";
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

    launchd.agents = {
      # The rank itself. Started/stopped exclusively by the link watcher —
      # RunAtLoad=false + KeepAlive=false means an unplugged cable and
      # rebuilds leave it idle. Interactive QoS: Background clamps Metal
      # decode throughput (same lesson as the normal-mode server agent).
      mlx-cluster-rank = {
        enable = true;
        config = {
          Label = rankLabel;
          # Launcher first: it discovers the link at runtime (iface, addresses,
          # ibv device), exports MLX_JACCL_COORDINATOR / MLX_IBV_DEVICES, and
          # execs the serve args that follow it.
          ProgramArguments = [ (lib.getExe clusterRankLauncherPkg) ] ++ clusterRankArgs;
          RunAtLoad = false;
          KeepAlive = false;
          ThrottleInterval = 60;
          ProcessType = "Interactive";
          AbandonProcessGroup = false;
          EnvironmentVariables = {
            HF_HOME = cfg.huggingFaceHome;
            MLX_RANK = if isCoordinator then "0" else "1";
            CLUSTER_ROLE = ncfg.role;
            CLUSTER_LINK_DISCOVERY = ncfg.linkDiscovery;
            CLUSTER_RENDEZVOUS_PORT = toString ncfg.rendezvousPort;
            # Faster GPU/CPU synchronization for distributed decode.
            MLX_METAL_FAST_SYNCH = "1";
          }
          // lib.optionalAttrs isStatic {
            CLUSTER_STATIC_COORDINATOR_IP = ncfg.staticLinkIps.coordinator;
          }
          // lib.optionalAttrs (ncfg.interfaceOverride != null) {
            CLUSTER_IFACE_OVERRIDE = ncfg.interfaceOverride;
          }
          // lib.optionalAttrs (ncfg.rdmaDevice != null) {
            CLUSTER_RDMA_DEVICE = ncfg.rdmaDevice;
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
            CLUSTER_LINK_DISCOVERY = ncfg.linkDiscovery;
            CLUSTER_RANK_LABEL = rankLabel;
            CLUSTER_WARMUP_LABEL = warmupAgentLabel;
            CLUSTER_NORMAL_PROXY = "http://127.0.0.1:${toString cfg.port}";
            CLUSTER_STATE_FILE = stateFile;
            CLUSTER_MAX_KICKSTARTS = toString ncfg.maxKickstarts;
            CLUSTER_ALERT_URL_FILE = ncfg.alertUrlFile;
          }
          // lib.optionalAttrs isCoordinator {
            # Readiness probe target: launchctl liveness alone cannot see a
            # rank hung in distributed init (see the watcher script).
            CLUSTER_HTTP_PORT = toString ncfg.httpPort;
          }
          // lib.optionalAttrs isStatic {
            CLUSTER_STATIC_PEER_IP = staticPeerIp;
          }
          // lib.optionalAttrs (ncfg.interfaceOverride != null) {
            CLUSTER_IFACE_OVERRIDE = ncfg.interfaceOverride;
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
