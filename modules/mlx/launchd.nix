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
    llamaSwapPkg
    llamaSwapConfigFile
    llamaSwapRuntimeConfigPath
    ;
in
{
  config = lib.mkIf cfg.enable {
    # ==========================================================================
    # LaunchAgent for Auto-Start
    # ==========================================================================
    # llama-swap proxy listens on the API port and manages vllm-mlx child
    # processes on ephemeral ports (startPort = 11436+). HardResourceLimits
    # is omitted — it would only cap the proxy process, not the vllm-mlx
    # children where the actual memory lives. As a result, programs.mlx.memoryHardLimitGb
    # is not enforced under the llama-swap architecture; primary OOM protection
    # is --cache-memory-mb on each vllm-mlx backend (set in the generated config).
    launchd.agents.vllm-mlx = {
      enable = true;
      config = {
        Label = launchAgentLabel;
        ProgramArguments = [
          (lib.getExe llamaSwapPkg)
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
        # Background = Jetsam-eligible (applies to proxy; vllm-mlx children inherit separately).
        ProcessType = "Background";
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

    # ==========================================================================
    # Watchdog LaunchAgent — defense in depth against nix-ai#801
    # ==========================================================================
    # Periodic check (default every 5 min) that kicks the vllm-mlx LaunchAgent
    # when any of:
    #   - A vllm-mlx serve worker has been alive longer than ttlGraceMult ×
    #     its configured ttl (stuck-past-TTL — the upstream llama-swap
    #     proxy/process.go:280-289 race fingerprint).
    #   - vm.swapusage used / total > swapThresholdPct.
    #   - Any single worker RSS > rssThresholdPct % of physical RAM.
    # The "kick" is `launchctl kickstart -k <label>` which forces a clean
    # restart through the existing KeepAlive + 120 s ThrottleInterval — no
    # graceful-shutdown ladder, no orphaned workers.
    # See programs.mlx.watchdog.* options for tuning.
    launchd.agents.vllm-mlx-watchdog = lib.mkIf cfg.watchdog.enable {
      enable = true;
      config = {
        Label = "${launchAgentLabel}.watchdog";
        ProgramArguments = [
          (lib.getExe (
            pkgs.writeShellApplication {
              name = "mlx-watchdog";
              runtimeInputs = with pkgs; [
                coreutils
                gawk
                gnused
                jq
              ];
              text = builtins.readFile ./scripts/mlx-watchdog.sh;
            }
          ))
        ];
        RunAtLoad = false;
        StartInterval = cfg.watchdog.intervalSeconds;
        ProcessType = "Background";
        AbandonProcessGroup = false;
        EnvironmentVariables = {
          MLX_LAUNCHD_LABEL = launchAgentLabel;
          MLX_WATCHDOG_LOG = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/watchdog.log";
          MLX_WATCHDOG_CONFIG = llamaSwapRuntimeConfigPath;
          MLX_WATCHDOG_SWAP_PCT = toString cfg.watchdog.swapThresholdPct;
          MLX_WATCHDOG_RSS_PCT = toString cfg.watchdog.rssThresholdPct;
          MLX_WATCHDOG_TTL_MULT = toString cfg.watchdog.ttlGraceMult;
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/watchdog.stdout.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/watchdog.error.log";
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
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/watchdog.log              :              644   3      1024  *     J
        ${config.home.homeDirectory}/Library/Logs/vllm-mlx/watchdog.error.log        :              644   3      1024  *     J
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
