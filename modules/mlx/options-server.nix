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

    # Sibling of programs.mlx.modelServerBackend (./options-runtime.nix, which
    # is at the file-size ceiling): the backend picks the IMPLEMENTATION, this
    # picks WHICH BUILD of the mlx-lm backend serves one model.
    modelServerVariant = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.enum [
          "release"
          "git"
        ]
      );
      default = { };
      example = lib.literalExpression ''{ "mlx-community/<deepseek-v4-quant>" = "git"; }'';
      description = ''
        Per-physical-model choice of mlx-lm wrapper: "release" (default — the
        harmony-patched release wheel) or "git" (the pinned git wheel, see
        lib/versions.nix mlxLmGit). Only a model whose architecture no mlx-lm
        release implements belongs on "git": that wheel does NOT carry the
        harmony tool-call patch, so a harmony model served from it loses tool
        calling with no error. ./options-catalog.nix compiles this from the
        catalog entry's serverVariant and asserts which entries may say "git".

        Temporary by construction — when a released mlx-lm covers the model,
        move the entry back to "release" and retire the pin.
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
