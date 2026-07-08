#
# MLX Module — LaunchAgent & Log Rotation
#
# macOS LaunchAgent configuration for the vllm-mlx inference server,
# plus newsyslog log rotation.
#
{
  config,
  lib,
  mlxShared,
  ...
}:
let
  inherit (mlxShared)
    cfg
    launchAgentLabel
    apiUrl
    mlxWarmupPkg
    llamaSwapPkg
    llamaSwapConfigFile
    mlxLmServerPkg
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
            # The config is the immutable Nix store file — nothing mutates it at
            # runtime (the old mutable-copy + --watch-config + discovery-scanner
            # machinery is gone; non-registry models are served by the dynamic
            # tier below). A config change is a darwin-rebuild, which restarts
            # this agent with the new store path.
            ProgramArguments = [
              (lib.getExe llamaSwapPkg)
              "--config"
              "${llamaSwapConfigFile}"
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
            # Do not abandon the process group; ensure child vllm-mlx processes
            # are terminated when launchd stops the proxy.
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

        # Dynamic tier: mlx_lm.server started with NO model argument natively
        # serves the ENTIRE HuggingFace cache — /v1/models lists every locally
        # downloaded model, and any request may name any cached model id, which
        # it loads on demand (mlx-lm's documented per-request ModelProvider
        # behavior). The HF cache itself is the single source of truth for
        # exposure: `hf download` a model and it is servable; delete it from the
        # cache and it is gone. Zero per-model config, zero discovery scanners.
        # The tuned resident tier (llama-swap + the Nix role registry above)
        # keeps the performance path; this tier is for everything else.
        mlx-lm-dynamic = lib.mkIf cfg.dynamicTier.enable {
          enable = true;
          config = {
            Label = "dev.mlx-lm.dynamic";
            ProgramArguments = [
              (lib.getExe mlxLmServerPkg)
              "--host"
              cfg.host
              "--port"
              (toString cfg.dynamicTier.port)
            ];
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 120;
            ProcessType = cfg.processType;
            EnvironmentVariables = {
              HF_HOME = cfg.huggingFaceHome;
            };
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/mlx-lm-dynamic.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/mlx-lm-dynamic.error.log";
          };
        };

        # One-shot warmup job: wait for the proxy to answer, then fault each
        # preloaded model with a 1-token chat completion so the weights are
        # resident at boot instead of on first user request.
        vllm-mlx-warmup = {
          enable = true;
          config = {
            Label = "dev.vllm-mlx.warmup";
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
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/mlx-lm-dynamic.log        :              644   3      10240 *     J
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/mlx-lm-dynamic.error.log  :              644   3      10240 *     J
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
