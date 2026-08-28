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
    warmupTimeoutSeconds
    llamaSwapLaunchPkg
    llamaSwapConfigFile
    llamaSwapConfigAttrs
    llamaSwapRuntimeConfigPath
    modelServerProcessPattern
    allModels
    ;
  # Worker ports llama-swap could hand out to a model in the CURRENT config —
  # an overestimate under programs.mlx.singleModel is safe (a few extra ports
  # get scanned and come back empty), an underestimate would not be. See
  # scripts/llama-swap-reap.sh for what these protect and why.
  workerPortCount = builtins.length (builtins.attrNames allModels);
  # Restart/re-attempt throttle shared by both agents below: 120s covers a
  # 70GB model load (20-60s) with margin, and is also the min-interval floor
  # handed to mlx-warmup.py (MLX_WARMUP_MIN_INTERVAL_SECONDS) so an external
  # `launchctl kickstart -k` — which bypasses ThrottleInterval entirely, that
  # is its whole purpose — cannot re-acquire the warmup concurrency slot any
  # faster than launchd's own restart already paces it. One number, two
  # enforcement points, so they cannot drift apart.
  restartThrottleSeconds = 120;
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
            # Apple's interpreter, per programs.mlx.appleInterpreter — the same
            # convention the cluster agents use. This one serves on loopback, so
            # it is not currently gated on Local Network; it follows the
            # convention anyway because the estate keeps ONE way of launching a
            # shell agent rather than two. The moment an agent's traffic leaves
            # loopback the Nix-shebang form starts failing silently, and by then
            # nobody remembers which form this file happened to use.
            ProgramArguments = lib.optional (cfg.appleInterpreter != null) cfg.appleInterpreter ++ [
              (lib.getExe llamaSwapLaunchPkg)
              "--config"
              llamaSwapRuntimeConfigPath
              "--watch-config"
              "--listen"
              "${cfg.host}:${toString cfg.port}"
            ];
            RunAtLoad = true;
            KeepAlive = true;
            # 70GB model loads take 20-60s, prevents rapid crash-restart loops (closes #256)
            ThrottleInterval = restartThrottleSeconds;
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
              # Consumed by llama-swap-launch's port-ownership reap (see
              # scripts/llama-swap-reap.sh) — NOT the process pattern above,
              # which that reap no longer trusts.
              MLX_PORT = toString cfg.port;
              MLX_WORKER_PORT_RANGE_START = toString llamaSwapConfigAttrs.startPort;
              MLX_WORKER_PORT_COUNT = toString workerPortCount;
            }
            // lib.optionalAttrs (cfg.telemetry.enable && cfg.telemetry.otlpEndpoint != null) {
              # Standard OTel env vars inherited by llama-swap and mlx_lm.server
              # children. The collector fans out to the log platform and
              # (optionally) to the eval platform — see
              # docs/adr/0003-galileo-ai-observability.md. Gated on a non-null
              # endpoint: there is no default, because the previous loopback
              # default served nothing and exported into a black hole.
              OTEL_SERVICE_NAME = "mlx-model-server";
              # Base URL only — the exporter appends the signal path itself.
              OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.otlpEndpoint;
              OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
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
        #
        # KeepAlive.SuccessfulExit=false restarts on ANY nonzero exit, with no
        # ceiling of its own — mlx-warmup.py bounds that itself: after a
        # capped run of consecutive full-cycle failures it exits 0 (a clean,
        # deliberate give-up, not a success) so this stops restarting it
        # rather than re-acquiring the model's concurrency slot forever. See
        # mlx-warmup.py's MAX_CONSECUTIVE_FAILURES for the restart-livelock
        # fix itself; ThrottleInterval below only paces launchd's OWN restarts.
        #
        # ThrottleInterval does NOT pace an external `launchctl kickstart -k`
        # of this label — bypassing the throttle is what kickstart -k is FOR.
        # Both cluster-link-helpers.sh (restore_normal_serving) and
        # mlx-default.sh kickstart this agent directly, and a caller that
        # retries a failing operation in a loop and calls
        # restore_normal_serving() on every attempt re-triggers a full warm
        # cycle every time with no cooldown from launchd's side at all. See
        # mlx-warmup.py's RE-INVOCATION BOUND (MLX_WARMUP_MIN_INTERVAL_SECONDS
        # below) for the fix — a second, independent bound on how often this
        # process will actually attempt a warm, regardless of trigger.
        mlx-model-server-warmup = {
          enable = true;
          config = {
            Label = warmupAgentLabel;
            ProgramArguments = [ (lib.getExe mlxWarmupPkg) ];
            RunAtLoad = true;
            KeepAlive = {
              SuccessfulExit = false;
            };
            ThrottleInterval = restartThrottleSeconds;
            ProcessType = "Background";
            EnvironmentVariables = {
              MLX_API_URL = apiUrl;
              MLX_WARMUP_MIN_INTERVAL_SECONDS = toString restartThrottleSeconds;
              MLX_PRELOAD_MODELS = lib.concatStringsSep " " cfg.preload;
              MLX_PRELOAD_MODELS_JSON = builtins.toJSON cfg.preload;
              MLX_WARMUP_TIMEOUT_SECONDS = toString warmupTimeoutSeconds;
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
      activation = {
        seedLlamaSwapConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${pkgs.python3}/bin/python3 "${./seed-config.py}" "${llamaSwapConfigFile}" "${llamaSwapRuntimeConfigPath}"
        '';

        # Auto-discover newly downloaded HF models and register them with llama-swap.
        # Runs after seeding so the runtime config exists. The script exits 0 when
        # the HF volume is absent or nothing new is found; a nonzero exit means a
        # real failure (e.g. the preload entry can't be resolved to a models[]
        # entry). Guard on a non-empty preload: a host with `preload = [ ]` cannot
        # derive a default model, so the script would exit 1 by design — skip
        # discovery there instead of aborting the rebuild.
        discoverMlxModels = lib.hm.dag.entryAfter [ "seedLlamaSwapConfig" ] (
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

        # Re-point the "default" alias at the runtime override, if set. Runs on
        # EVERY activation and LAST, so a rebuild cannot clobber an operator's
        # override. An unusable override logs loudly and falls back to the
        # declared key rather than aborting the rebuild.
        applyMlxDefaultModelOverride = lib.hm.dag.entryAfter [ "discoverMlxModels" ] ''
          export MLX_LLAMA_SWAP_CONFIG="${llamaSwapRuntimeConfigPath}"
          export MLX_DEFAULT_MODEL_KEYMAP="${cfg.defaultModelKeymapFile}"
          export MLX_DEFAULT_MODEL_OVERRIDE="${cfg.defaultModelOverridePath}"
          run ${pkgs.python3}/bin/python3 "${./default-model.py}" apply
        '';
      };
    };

  };
}
