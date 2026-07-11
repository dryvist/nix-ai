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
# Link identity is ZERO-CONFIG: the cabled Thunderbolt port is auto-detected
# at runtime and its automatic IPv6 link-local (fe80::) is the address — no
# IP is written in any repo (see the linkDiscovery option for the JACCL gate
# + static fallback). RDMA prerequisites: `rdma_ctl enable` from Recovery on
# BOTH Macs; nix-darwin `system.rdmaLink` detaches the cabled port from the
# Thunderbolt bridge at activation. Verify devices with `ibv_devices`.
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
  isStatic = ncfg.linkDiscovery == "static";
  staticPeerIp = if isCoordinator then ncfg.staticLinkIps.worker else ncfg.staticLinkIps.coordinator;

  # The serve invocation stays a plain args list (appended after the launcher)
  # so lib/checks/mlx-night.nix can assert it in pure eval; the launcher only
  # computes MLX_JACCL_COORDINATOR / MLX_IBV_DEVICES at runtime and execs it.
  nightRankArgs = [
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
    text =
      builtins.readFile ./scripts/night-link-lib.sh + builtins.readFile ./scripts/night-link-watcher.sh;
  };

  nightRankLauncherPkg = pkgs.writeShellApplication {
    name = "mlx-night-rank-launcher";
    text =
      builtins.readFile ./scripts/night-link-lib.sh + builtins.readFile ./scripts/night-rank-launcher.sh;
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

    linkDiscovery = lib.mkOption {
      type = lib.types.enum [
        "link-local"
        "static"
      ];
      default = "link-local";
      description = ''
        "link-local" (default): zero written IP — auto-detected port, IPv6
        fe80:: identity, peer via all-nodes multicast. GATE: JACCL accepting
        a scoped link-local rendezvous is unvalidated until a supervised
        cluster night. "static": the fallback — role-derived synthetic IPs
        from staticLinkIps (pin per host via rdmaLink.staticAddress).
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
          # Launcher first: it discovers the link at runtime (iface, addresses,
          # ibv device), exports MLX_JACCL_COORDINATOR / MLX_IBV_DEVICES, and
          # execs the serve args that follow it.
          ProgramArguments = [ (lib.getExe nightRankLauncherPkg) ] ++ nightRankArgs;
          RunAtLoad = false;
          KeepAlive = false;
          ThrottleInterval = 60;
          ProcessType = "Interactive";
          AbandonProcessGroup = false;
          EnvironmentVariables = {
            HF_HOME = cfg.huggingFaceHome;
            MLX_RANK = if isCoordinator then "0" else "1";
            NIGHT_ROLE = ncfg.role;
            NIGHT_LINK_DISCOVERY = ncfg.linkDiscovery;
            NIGHT_RENDEZVOUS_PORT = toString ncfg.rendezvousPort;
            # Faster GPU/CPU synchronization for distributed decode.
            MLX_METAL_FAST_SYNCH = "1";
          }
          // lib.optionalAttrs isStatic {
            NIGHT_STATIC_COORDINATOR_IP = ncfg.staticLinkIps.coordinator;
          }
          // lib.optionalAttrs (ncfg.interfaceOverride != null) {
            NIGHT_IFACE_OVERRIDE = ncfg.interfaceOverride;
          }
          // lib.optionalAttrs (ncfg.rdmaDevice != null) {
            NIGHT_RDMA_DEVICE = ncfg.rdmaDevice;
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
            NIGHT_LINK_DISCOVERY = ncfg.linkDiscovery;
            NIGHT_RANK_LABEL = rankLabel;
            NIGHT_WARMUP_LABEL = warmupAgentLabel;
            NIGHT_DAY_PROXY = "http://127.0.0.1:${toString cfg.port}";
            NIGHT_STATE_FILE = stateFile;
          }
          // lib.optionalAttrs isStatic {
            NIGHT_STATIC_PEER_IP = staticPeerIp;
          }
          // lib.optionalAttrs (ncfg.interfaceOverride != null) {
            NIGHT_IFACE_OVERRIDE = ncfg.interfaceOverride;
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
