#
# MLX Module — LaunchAgents
#
# macOS LaunchAgent configuration for official mlx_lm.server workers.
# Log rotation is NOT here — see programs.agent-log-rotation in nix-darwin.
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
    llamaSwapLaunchPkg
    llamaSwapConfigFile
    llamaSwapRuntimeConfigPath
    modelServerProcessPattern
    ;
in
{
  config = lib.mkIf cfg.enable {
    launchd = {
      # ==========================================================================
      # LaunchAgent for Auto-Start
      # ==========================================================================
      # llama-swap proxy listens on the API port and manages mlx_lm.server child
      # processes on ephemeral ports (startPort = 11436+). HardResourceLimits
      # is omitted — it would only cap the proxy process, not the mlx_lm.server
      # children where the actual memory lives (and macOS does not reliably
      # enforce RSS rlimits). The host iogpu.wired_limit_mb value is the hard
      # Metal guardrail. Official mlx_lm additionally receives the declared
      # cacheMemoryMb as --prompt-cache-bytes, and programs.mlx.memoryHardLimitGb
      # is enforced in-process by the mlx_lm launcher (mx.set_memory_limit /
      # mx.set_cache_limit). vllm-only utilization and worker-unload options
      # remain preserved but inactive for mlx_lm.
      agents = {
        mlx-model-server = {
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
              MLX_MODEL_SERVER_PROCESS_PATTERN = modelServerProcessPattern;
            }
            // lib.optionalAttrs cfg.telemetry.enable {
              # Standard OTel env vars inherited by llama-swap and mlx_lm.server children.
              # The OTEL Collector at :30317 fans out to Cribl/Splunk and (optionally)
              # to Galileo — see docs/adr/0003-galileo-ai-observability.md.
              OTEL_SERVICE_NAME = "mlx-model-server";
              OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.otlpEndpoint;
              OTEL_EXPORTER_OTLP_PROTOCOL = "grpc";
              OTEL_RESOURCE_ATTRIBUTES = "service.namespace=mlx,deployment.environment=homelab";
            };
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/server.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/server.error.log";
          };
        };

        # One-shot warmup job: wait for the proxy to answer, then fault each
        # preloaded model with a 1-token chat completion so the weights are
        # resident at boot instead of on first user request. Also kickstarted
        # by mlx-default.sh after every proxy restart (via MLX_WARMUP_LABEL) —
        # this is the ONLY preload path; llama-swap's hooks.on_startup.preload
        # is deliberately not emitted because its request shape is not
        # portable across the preserved MLX backends.
        mlx-model-server-warmup = {
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
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/warmup.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/warmup.error.log";
          };
        };

        # Serving watchdog lives in launchd-watchdog.nix (split for size).
      };
    };

    home = {
      # Log rotation (#255) is NOT here. It lives in nix-darwin's
      # programs.agent-log-rotation, as an /etc/newsyslog.d entry run by the
      # system newsyslog as root. It cannot live in home-manager: newsyslog
      # refuses to run as anyone but root — the check is in the binary, so even
      # `newsyslog -n` fails — which is why the user LaunchAgent that used to be
      # here sat at exit status 1 every hour while server.log grew past 40 MB.

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
      # the HF volume is absent or nothing new is found; a nonzero exit means a
      # real failure (e.g. the preload entry can't be resolved to a models[]
      # entry). Guard on a non-empty preload: a host with `preload = [ ]` cannot
      # derive a default model, so the script would exit 1 by design — skip
      # discovery there instead of aborting the rebuild.
      activation.discoverMlxModels = lib.hm.dag.entryAfter [ "seedLlamaSwapConfig" ] (
        lib.optionalString (cfg.preload != [ ]) ''
          export MLX_HF_HOME="${cfg.huggingFaceHome}"
          export MLX_LLAMA_SWAP_CONFIG="${llamaSwapRuntimeConfigPath}"
          export MLX_LLAMA_SWAP_BASE_CONFIG="${llamaSwapConfigFile}"
          export MLX_PRELOAD_MODELS_JSON=${lib.escapeShellArg (builtins.toJSON cfg.preload)}
          # Fail loud: a swallowed nonzero exit here left the runtime config
          # stale across rebuilds while models sat unregistered (#1270). Surface
          # the script's stderr and abort activation so the failure is visible
          # instead of looking like a silent no-op.
          if ! run ${pkgs.python3}/bin/python3 "${./discover-models.py}" --quiet; then
            errorEcho "discoverMlxModels: model discovery failed (see errors above); llama-swap runtime config left unchanged"
            exit 1
          fi
        ''
      );
    };

  };
}
