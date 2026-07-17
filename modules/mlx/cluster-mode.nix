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
  inherit (mlxShared) cfg warmupAgentLabel;
  ncfg = cfg.clusterMode;
  versions = import ../../lib/versions.nix;

  rankLabel = "dev.mlx-cluster.rank";
  watcherLabel = "dev.mlx-cluster.watcher";
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  stateFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/link-state";
  ibvMatrixFile = "${config.home.homeDirectory}/.config/mlx-cluster/ibv-matrix.json";

  isCoordinator = ncfg.role == "coordinator";
  staticPeerIp = if isCoordinator then ncfg.staticLinkIps.worker else ncfg.staticLinkIps.coordinator;

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
    text = builtins.readFile ./scripts/cluster-link-watcher.sh;
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

    rdmaDevice = lib.mkOption {
      type = lib.types.str;
      default = "rdma_en2";
      description = ''
        RDMA device name for the MLX_IBV_DEVICES matrix (see `ibv_devices`).
        Port-dependent: validate on the first plug session and override per
        host if the cable lands on a different port.
      '';
    };

    wiredLimitMb = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 90000;
      description = ''
        iogpu.wired_limit_mb the watcher applies (sudo, exact-value grant
        from nix-darwin clusterLinkPrep) before starting the rank — sized for
        this node's pipeline shard, leaving the GUI working set unwirable.
        null = never touch the sysctl. When set, a failed apply SKIPS the
        rank start: serving a shard over a day-sized ceiling is the
        2026-07-12 dual-host panic.
      '';
    };

    dayWiredLimitMb = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        iogpu.wired_limit_mb the watcher restores at link-down (0 = macOS
        default ceiling). Must equal the value nix-darwin grants
        (appleSiliconTunables.wiredLimitMb, else 0).
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
            CLUSTER_DAY_WIRED_LIMIT_MB = toString ncfg.dayWiredLimitMb;
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
