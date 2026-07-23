#
# MLX Module — Server endpoint options
#
# Network surface (port/host) and the model-cache mount point. Plus the
# default-model passthrough that ties this server to the ai-stack registry.
#
{ config, lib, ... }:
let
  aiStackVars = import ../../vars/ai-stack.nix;
in
{
  options.programs.mlx = {
    enable = lib.mkEnableOption "MLX inference server";

    defaultModel = lib.mkOption {
      type = lib.types.str;
      inherit (config.services.aiStack.models) default;
      defaultText = lib.literalExpression "config.services.aiStack.models.default";
      description = ''
        Physical mlx-community/ HuggingFace model ID for the "default" role.
        Sourced from services.aiStack.models.default — see
        nix-ai/modules/ai-stack/default.nix for the registry.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port for the MLX model server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address for the MLX model server";
    };

    huggingFaceHome = lib.mkOption {
      type = lib.types.str;
      default = "/Volumes/HuggingFace";
      description = "Path to HuggingFace model cache (dedicated APFS volume)";
    };

    # Retained for the disabled vllm-mlx backend, whose native
    # --enable-metrics flag exposes /metrics on each worker. The active
    # mlx_lm backend does not consume this option.
    enableMetrics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose native Prometheus metrics when the selected MLX backend supports them.";
    };

    telemetry = {
      enable = lib.mkEnableOption "OpenTelemetry trace export from the MLX inference stack";

      otlpEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:${toString aiStackVars.nodeports.otel_grpc}";
        description = ''
          gRPC OTLP endpoint for the OpenTelemetry Collector.
          Matches the existing Claude Code telemetry pipeline endpoint.
        '';
      };
    };
  };
}
