#
# MLX Module — Server endpoint options
#
# Network surface (port/host) and the model-cache mount point. Plus the
# default-model passthrough that ties this server to the ai-stack registry.
#
{ config, lib, ... }:
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
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://otel.example.internal";
        description = ''
          OTLP/HTTP base URL for the OpenTelemetry Collector — no `/v1/...`
          suffix, the exporter appends the signal path itself. Matches the
          Claude Code telemetry pipeline endpoint
          (userConfig.telemetry.otlpEndpoint).

          Null by default, and null means no export even when `enable` is true.
          No fallback default is provided on purpose: this previously defaulted
          to a loopback port nothing served, so the agent exported into a black
          hole indistinguishable from working telemetry.

          Setting this is currently NOT sufficient to get telemetry out of MLX.
          These variables are inherited by llama-swap and the mlx_lm.server
          children, but no component in that chain is OpenTelemetry-instrumented
          — scanning the installed mlx_lm package and the llama-swap binary
          finds no OpenTelemetry reference in either. The option is kept because
          the environment is the right shape the moment either gains
          instrumentation; until then, a configured endpoint here means nothing
          is being emitted, not that emission is going somewhere.
        '';
      };
    };
  };
}
