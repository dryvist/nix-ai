#
# MLX Module — LaunchAgent & Log Rotation
#
# macOS LaunchAgent configuration for the vllm-mlx inference server,
# plus newsyslog log rotation.
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
    launchAgentLabel
    warmupAgentLabel
    apiUrl
    mlxWarmupPkg
    mlxWatchdogPkg
    llamaSwapLaunchPkg
    llamaSwapConfigFile
    llamaSwapRuntimeConfigPath
    ;
in
{
  config = lib.mkIf cfg.enable {
    launchd = {
      # ==========================================================================
      # LaunchAgent for Auto-Start
      # ==========================================================================
      # llama-swap proxy listens on the API port and manages vllm-mlx child
      # processes on ephemeral ports (startPort = 11436+). HardResourceLimits
      # is omitted — it would only cap the proxy process, not the vllm-mlx
      # children where the actual memory lives (and macOS does not reliably
      # enforce RSS rlimits). Per-worker OOM protection is native and inside
      # each worker: --gpu-memory-utilization (Metal allocation ceiling +
      # emergency cache clear; programs.mlx.gpuMemoryUtilization) plus
      # --cache-memory-mb and --auto-unload-idle-seconds (set in the generated
      # config). programs.mlx.memoryHardLimitGb remains declarative intent only.
      agents = {
        vllm-mlx = {
          enable = true;
          config = {
            Label = launchAgentLabel;
            ProgramArguments = [
              (lib.getExe llamaSwapLaunchPkg)
              "--config"
              llamaSwapRuntimeConfigPath
              "--watch-config"
              "--listen"
              "${cfg.host}:${toString cfg.port}"
            ];
            RunAtLoad = true;
            KeepAlive = true;
            # 2 min throttle — 70GB model loads take 20-60s, prevents rapid crash-restart loops (closes #256)
            ThrottleInterval = 120;
            # Interactive by default — Background QoS clamps Metal decode ~8x
            # (see options-runtime.nix processType). OOM backstop is the RSS
            # hard limit, not Jetsam eligibility.
            ProcessType = cfg.processType;
            # Do not abandon the process group. This is necessary but NOT
            # sufficient: workers are spawned through `uv tool uvx`, so the real
            # engine is a grandchild and has been observed surviving a stop
            # (re-parented to init) still holding its port. llama-swap-launch.sh
            # reaps those on the way back up — that is the load-bearing half.
            AbandonProcessGroup = false;
            EnvironmentVariables = {
              HF_HOME = cfg.huggingFaceHome;
            }
            // lib.optionalAttrs cfg.telemetry.enable {
              # Standard OTel env vars inherited by llama-swap and its vllm-mlx children.
              # The OTEL Collector at :30317 fans out to Cribl/Splunk and (optionally)
              # to Galileo — see docs/adr/0003-galileo-ai-observability.md.
              # Trace emission from vllm-mlx 0.2.9 is best-effort; the collector's
              # routing connector is the primary gate, not the agent env.
              OTEL_SERVICE_NAME = "vllm-mlx";
              OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.otlpEndpoint;
              OTEL_EXPORTER_OTLP_PROTOCOL = "grpc";
              OTEL_RESOURCE_ATTRIBUTES = "service.namespace=mlx,deployment.environment=homelab";
            };
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx.error.log";
          };
        };

        # One-shot warmup job: wait for the proxy to answer, then fault each
        # preloaded model with a 1-token chat completion so the weights are
        # resident at boot instead of on first user request. Also kickstarted
        # by mlx-default.sh after every proxy restart (via MLX_WARMUP_LABEL) —
        # this is the ONLY preload path; llama-swap's hooks.on_startup.preload
        # is deliberately not emitted (its request shape 404s vllm-mlx, #1175).
        vllm-mlx-warmup = {
          enable = true;
          config = {
            Label = warmupAgentLabel;
            ProgramArguments = [ (lib.getExe mlxWarmupPkg) ];
            RunAtLoad = true;
            KeepAlive = {
              SuccessfulExit = false;
            };
            ThrottleInterval = 120;
            ProcessType = "Background";
            EnvironmentVariables = {
              MLX_API_URL = apiUrl;
              MLX_PRELOAD_MODELS = lib.concatStringsSep " " cfg.preload;
              MLX_PRELOAD_MODELS_JSON = builtins.toJSON cfg.preload;
            };
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-warmup.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-warmup.error.log";
          };
        };

        # Serving watchdog: KeepAlive=true only restarts the proxy on process
        # EXIT, so every "up but not serving" mode is invisible to launchd — a
        # llama-swap zombie, a wedged batch scheduler answering 200 with zero
        # tokens, or a port-holding orphan making the proxy 429 everything. All
        # three keep /v1/models green, so this probes a REAL completion every
        # StartInterval and kickstarts the server agent when no token comes back.
        # The script self-gates re-fires with a cooldown marker so a slow model
        # reload is not restart-stormed (mlx-watchdog.sh).
        vllm-mlx-watchdog = {
          # The probe generates against the first preloaded (resident) model, so
          # with nothing preloaded every probe would cold-load a worker — worse
          # than no watchdog. Such a host has no resident serving to guard.
          enable = cfg.preload != [ ];
          config = {
            Label = "dev.vllm-mlx.watchdog";
            ProgramArguments = [ (lib.getExe mlxWatchdogPkg) ];
            RunAtLoad = false;
            # 60 s: a zombie is detected and kickstarted within one cron gap
            # (crons fire every ~15 min), so the following tick finds it healthy.
            StartInterval = 60;
            ProcessType = "Background";
            EnvironmentVariables = {
              MLX_API_URL = apiUrl;
              MLX_LAUNCHD_LABEL = launchAgentLabel;
              # Probe the first resident model: it is warm by construction, so a
              # failure means "not serving", never "cold load in progress".
              MLX_WATCHDOG_PROBE_MODEL = lib.head cfg.preload;
            };
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-watchdog.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-watchdog.error.log";
          };
        };
      };
    };

    home = {
      # ==========================================================================
      # Log Rotation (closes #255)
      # ==========================================================================
      # newsyslog rotates logs when they exceed 10MB, keeping 3 compressed archives.
      # Stock macOS newsyslog only reads /etc/newsyslog.d/ (requires root), so a
      # companion LaunchAgent invokes it hourly with our user-level config.
      file.".config/newsyslog.d/vllm-mlx.conf".text = ''
        # logfilename                                                                [owner:group]  mode  count  size  when  flags
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx.error.log        :              644   3      10240 *     J
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx.log              :              644   3      10240 *     J
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-warmup.error.log :              644   3      10240 *     J
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-warmup.log       :              644   3      10240 *     J
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-watchdog.error.log :            644   3      10240 *     J
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-watchdog.log     :              644   3      10240 *     J
      '';

      # ==========================================================================
      # Runtime Config Seeding and Model Discovery
      # ==========================================================================
      # On activation (darwin-rebuild switch), seed the mutable runtime config
      # from the Nix-generated base config. Preserves runtime-discovered models
      # by only overwriting when the base config has actually changed.
      activation.seedLlamaSwapConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.python3}/bin/python3 "${./seed-config.py}" "${llamaSwapConfigFile}" "${llamaSwapRuntimeConfigPath}"
      '';

      # Auto-discover newly downloaded HF models and register them with llama-swap.
      # Runs after seeding so the runtime config exists. The script exits 0 when
      # the HF volume is absent (scan_models returns []), so no || true needed.
      activation.discoverMlxModels = lib.hm.dag.entryAfter [ "seedLlamaSwapConfig" ] ''
        export MLX_HF_HOME="${cfg.huggingFaceHome}"
        export MLX_LLAMA_SWAP_CONFIG="${llamaSwapRuntimeConfigPath}"
        export MLX_LLAMA_SWAP_BASE_CONFIG="${llamaSwapConfigFile}"
        export MLX_PRELOAD_MODELS_JSON=${lib.escapeShellArg (builtins.toJSON cfg.preload)}
        run ${pkgs.python3}/bin/python3 "${./discover-models.py}" --quiet
      '';
    };

    launchd.agents.vllm-mlx-logrotate = {
      enable = true;
      config = {
        Label = "dev.vllm-mlx.logrotate";
        ProgramArguments = [
          "/usr/sbin/newsyslog"
          "-f"
          "${config.home.homeDirectory}/.config/newsyslog.d/vllm-mlx.conf"
        ];
        StartCalendarInterval = [ { Minute = 0; } ]; # hourly
      };
    };
  };
}
