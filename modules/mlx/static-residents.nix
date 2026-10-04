# Two always-loaded MLX resident servers. The catalog owns every model limit,
# the generated consumer file and the launch arguments are compiled from it.
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
    mlxModelServerPkgs
    mkModelArgs
    workerEnv
    ;
  gib = 1024 * 1024 * 1024;
  contracts = cfg.staticResidentContracts;
  byRole = lib.foldl' (
    acc: modelId: acc // lib.genAttrs (builtins.attrNames contracts.${modelId}.roles) (_: modelId)
  ) { } (builtins.attrNames contracts);
  judgeModelId = byRole.judge or null;
  judgeContract = if judgeModelId == null then { } else contracts.${judgeModelId};
  routerUrl = "http://127.0.0.1:${toString config.programs.litellmLocal.port}/v1";
  consumerConfig = {
    inherit routerUrl;
    models = lib.mapAttrs (
      _: contract:
      contract
      // {
        baseUrl = "http://127.0.0.1:${toString contract.servicePort}/v1";
        aliases = builtins.attrNames contract.roles;
      }
    ) contracts;
    aliases = byRole;
    clients = {
      ghGuard = lib.optionalAttrs (judgeModelId != null) {
        url = "${routerUrl}/chat/completions";
        model = "judge";
        inherit (judgeContract) timeoutSeconds;
      };
      recorder = {
        baseUrl = routerUrl;
        defaultModel = "fast";
        models = {
          default = "default";
          fast = "fast";
        };
      };
    };
  };
  agentFor =
    modelId: contract:
    let
      key = contract.catalogKey;
      label = contract.launchdLabel;
      command = lib.getExe mlxModelServerPkgs.${contract.backend};
      args = mkModelArgs modelId contract.servicePort ++ (cfg.modelExtraArgs.${modelId} or [ ]);
      logDir = "${config.home.homeDirectory}/Library/Logs/mlx-model-server";
      env =
        workerEnv modelId
        // {
          MLX_L1_MEMORY_LIMIT_BYTES = toString (cfg.memoryHardLimitGb * gib);
          MLX_MAX_PENDING_REQUESTS = toString contract.queueSize;
        }
        // lib.optionalAttrs (cfg.bufferCacheLimitGb != null) {
          MLX_L1_CACHE_LIMIT_BYTES = toString (cfg.bufferCacheLimitGb * gib);
        }
        // lib.optionalAttrs cfg.suppressWiredLimit {
          MLX_SUPPRESS_WIRED_LIMIT = "1";
        }
        // lib.optionalAttrs (cfg.telemetry.enable && cfg.telemetry.otlpEndpoint != null) {
          OTEL_SERVICE_NAME = "mlx-${key}";
          OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.otlpEndpoint;
          OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
          OTEL_RESOURCE_ATTRIBUTES = "service.namespace=mlx,deployment.environment=homelab";
        };
    in
    {
      name = if contract.roles ? default then "mlx-model-server" else "mlx-static-resident-${key}";
      value = {
        enable = true;
        config = {
          Label = label;
          ProgramArguments = [ command ] ++ args;
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 120;
          ProcessType = cfg.processType;
          AbandonProcessGroup = false;
          EnvironmentVariables = env;
          StandardOutPath = "${logDir}/${key}.log";
          StandardErrorPath = "${logDir}/${key}.error.log";
        };
      };
    };
  staticAgents = lib.mapAttrs' agentFor contracts;
in
{
  config = lib.mkIf (cfg.enable && contracts != { }) {
    assertions = [
      {
        assertion = builtins.length (builtins.attrNames contracts) <= 2;
        message = "programs.mlx may render at most two static resident model servers.";
      }
      {
        assertion = lib.all (contract: contract.backend != null) (lib.attrValues contracts);
        message = "each static resident must resolve a model-server backend.";
      }
      {
        assertion = config.programs.litellmLocal.enable;
        message = "static resident serving requires the local LiteLLM proxy for stable role aliases.";
      }
    ];
    launchd.agents = staticAgents;
    home = {
      file.".config/mlx/resident-model-limits.json".text = builtins.toJSON consumerConfig;
      sessionVariables = {
        MLX_RESIDENT_MODEL_LIMITS_FILE = "${config.home.homeDirectory}/.config/mlx/resident-model-limits.json";
      };
      activation.createStaticMlxLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "${config.home.homeDirectory}/Library/Logs/mlx-model-server"
      '';
    };
  };
}
