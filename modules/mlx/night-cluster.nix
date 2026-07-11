#
# MLX Module — Night Cluster (two-Mac JACCL distributed brain)
#
# Overnight, one Thunderbolt 5 cable turns two Macs into a single MLX
# pipeline-parallel cluster serving a frontier-class model that neither
# machine can hold alone. Each host runs its own rank from launchd (no SSH
# orchestration): a link watcher detects the cable, quiesces day serving,
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
# RDMA prerequisites: `rdma_ctl enable` on BOTH Macs (one-time). Bridge
# detach and link-address assignment are automatic — the nix-darwin
# night-link-prep daemon converges the role address onto whichever port the
# cable is in, and the rank launcher below derives the RDMA device from that
# interface at start. Moving the cable requires no config change anywhere.
# JACCL rendezvous is IPv4-only (verified 2026-07-11: every IPv6 form fails
# to parse), which is why the link keeps synthetic IPv4 addresses.
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
  ncfg = cfg.nightCluster;
  versions = import ../../lib/versions.nix;

  rankLabel = "dev.mlx-night.rank";
  watcherLabel = "dev.mlx-night.watcher";
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-night";
  stateFile = "${config.home.homeDirectory}/Library/Application Support/mlx-night/link-state";

  isCoordinator = ncfg.role == "coordinator";
  peerIp = if isCoordinator then ncfg.linkIps.worker else ncfg.linkIps.coordinator;

  # Runtime launcher: detects the interface carrying this host's link
  # address, writes the MLX_IBV_DEVICES matrix for its RDMA device, then
  # execs the rank command (its argv). Keeps the serving invocation visible
  # in ProgramArguments so lib/checks/mlx-night.nix still asserts it.
  rankLaunchPkg = pkgs.writeShellApplication {
    name = "mlx-night-rank-launch";
    text = builtins.readFile ./scripts/night-rank-launch.sh;
  };

  nightRankArgs = [
    (lib.getExe rankLaunchPkg)
    "${pkgs.uv}/bin/uvx"
    "--from"
    "mlx-lm==${versions.mlxLm}"
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

  nightWatcherPkg = pkgs.writeShellApplication {
    name = "mlx-night-link-watcher";
    runtimeInputs = [ pkgs.curl ];
    text = builtins.readFile ./scripts/night-link-watcher.sh;
  };
in
{
  options.programs.mlx.nightCluster = {
    enable = lib.mkEnableOption "two-Mac JACCL night cluster (mlx-lm pipeline-parallel serving)";

    role = lib.mkOption {
      type = lib.types.enum [
        "coordinator"
        "worker"
      ];
      description = "coordinator = rank 0, binds the night HTTP endpoint; worker = rank 1.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "mlx-community/GLM-4.7-4bit";
      description = ''
        HuggingFace id of the night brain. Must use an architecture with
        distributed support in the pinned mlx-lm (glm4_moe: pipeline).
        198 GB weights split across both ranks via --pipeline.
      '';
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 11440;
      description = "Night endpoint port on the coordinator (loopback; exposed via the host's gateway).";
    };

    rendezvousPort = lib.mkOption {
      type = lib.types.port;
      default = 11441;
      description = "JACCL coordinator rendezvous port (MLX_JACCL_COORDINATOR).";
    };

    linkIps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # Synthetic point-to-point net for the Thunderbolt cable itself —
        # module-defined defaults, not site topology. Assigned once per Mac
        # via networksetup (runbook step); override only on subnet clash.
        coordinator = "192.168.208.1";
        worker = "192.168.208.2";
      };
      description = "Link addresses of the two ends of the Thunderbolt cable.";
    };

    extraServerArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra mlx_lm.server args for the night rank.";
    };

    prefetch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Idempotently download the night model at agent load (retries until complete).";
    };

    quiesceCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Worker-side hook run at link-up before the rank starts (e.g. the night-quiesce allowlist sweep).";
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
        message = "programs.mlx.nightCluster: night ports must not clash with the day proxy port.";
      }
    ];

    launchd.agents = {
      # The rank itself. Started/stopped exclusively by the link watcher —
      # RunAtLoad=false + KeepAlive=false means unplugged mornings and
      # rebuilds leave it idle. Interactive QoS: Background clamps Metal
      # decode throughput (same lesson as the day server agent).
      mlx-night-rank = {
        enable = true;
        config = {
          Label = rankLabel;
          ProgramArguments = nightRankArgs;
          RunAtLoad = false;
          KeepAlive = false;
          ThrottleInterval = 60;
          ProcessType = "Interactive";
          AbandonProcessGroup = false;
          EnvironmentVariables = {
            HF_HOME = cfg.huggingFaceHome;
            MLX_RANK = if isCoordinator then "0" else "1";
            MLX_JACCL_COORDINATOR = "${ncfg.linkIps.coordinator}:${toString ncfg.rendezvousPort}";
            # MLX_IBV_DEVICES is generated at start by the rank launcher from
            # the detected interface.
            NIGHT_OWN_IP = if isCoordinator then ncfg.linkIps.coordinator else ncfg.linkIps.worker;
            # Faster GPU/CPU synchronization for distributed decode.
            MLX_METAL_FAST_SYNCH = "1";
          };
          StandardOutPath = "${logDir}/night-rank.log";
          StandardErrorPath = "${logDir}/night-rank.error.log";
        };
      };

      # Link watcher: one state-machine tick per interval (see the script for
      # the transition table).
      mlx-night-watcher = {
        enable = true;
        config = {
          Label = watcherLabel;
          ProgramArguments = [ (lib.getExe nightWatcherPkg) ];
          RunAtLoad = true;
          StartInterval = 30;
          ProcessType = "Background";
          EnvironmentVariables = {
            NIGHT_ROLE = ncfg.role;
            NIGHT_PEER_IP = peerIp;
            NIGHT_RANK_LABEL = rankLabel;
            NIGHT_WARMUP_LABEL = warmupAgentLabel;
            NIGHT_DAY_PROXY = "http://127.0.0.1:${toString cfg.port}";
            NIGHT_STATE_FILE = stateFile;
          }
          // lib.optionalAttrs (ncfg.quiesceCommand != null) {
            NIGHT_QUIESCE_CMD = ncfg.quiesceCommand;
          }
          // lib.optionalAttrs (ncfg.restoreCommand != null) {
            NIGHT_RESTORE_CMD = ncfg.restoreCommand;
          };
          StandardOutPath = "${logDir}/night-watcher.log";
          StandardErrorPath = "${logDir}/night-watcher.error.log";
        };
      };
    }
    // lib.optionalAttrs ncfg.prefetch {
      # One-shot idempotent prefetch; KeepAlive-until-success retries partial
      # downloads (198 GB) across failures, throttled by launchd.
      mlx-night-prefetch = {
        enable = true;
        config = {
          Label = "dev.mlx-night.prefetch";
          ProgramArguments = [
            "${pkgs.uv}/bin/uvx"
            "--from"
            "huggingface-hub==${versions.huggingfaceHub}"
            "hf"
            "download"
            ncfg.model
          ];
          RunAtLoad = true;
          KeepAlive = {
            SuccessfulExit = false;
          };
          ThrottleInterval = 300;
          ProcessType = "Background";
          EnvironmentVariables = {
            HF_HOME = cfg.huggingFaceHome;
          };
          StandardOutPath = "${logDir}/night-prefetch.log";
          StandardErrorPath = "${logDir}/night-prefetch.error.log";
        };
      };
    }
    // {
      # Bounded night logs, rotated hourly (offset from the day rotation).
      mlx-night-logrotate = {
        enable = true;
        config = {
          Label = "dev.mlx-night.logrotate";
          ProgramArguments = [
            "/usr/sbin/newsyslog"
            "-f"
            "${config.home.homeDirectory}/.config/newsyslog.d/mlx-night.conf"
          ];
          StartCalendarInterval = [ { Minute = 30; } ];
        };
      };
    };

    # newsyslog config consumed by mlx-night-logrotate (same pattern as the
    # day server's vllm-mlx.conf).
    home.file.".config/newsyslog.d/mlx-night.conf".text = ''
      # logfilename                                  [owner:group]  mode  count  size  when  flags
      ${logDir}/night-rank.log                       :              644   3      10240 *     J
      ${logDir}/night-rank.error.log                 :              644   3      10240 *     J
      ${logDir}/night-watcher.log                    :              644   3      10240 *     J
      ${logDir}/night-watcher.error.log              :              644   3      10240 *     J
      ${logDir}/night-prefetch.log                   :              644   3      10240 *     J
      ${logDir}/night-prefetch.error.log             :              644   3      10240 *     J
    '';
  };
}
