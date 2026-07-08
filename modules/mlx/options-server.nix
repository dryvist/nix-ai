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
    enable = lib.mkEnableOption "MLX inference server via vllm-mlx";

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
      description = "Port for the vllm-mlx API server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address for the vllm-mlx API server";
    };

    huggingFaceHome = lib.mkOption {
      type = lib.types.str;
      default = "/Volumes/HuggingFace";
      description = "Path to HuggingFace model cache (dedicated APFS volume)";
    };

    # Dynamic tier — mlx-lm's own OpenAI server with NO model argument: it
    # natively lists the entire HF cache at /v1/models and loads any requested
    # cached model id on demand. The cache is the single source of truth for
    # exposure (download = servable, delete = gone) — no per-model config, no
    # discovery scanner, no blocklist. The llama-swap registry above remains
    # the tuned resident tier; this serves everything else.
    dynamicTier = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run the zero-config dynamic model tier (mlx_lm.server over the whole
          HF cache). On by default: every mlx-enabled host exposes everything
          it has downloaded, with no per-model configuration anywhere.

          Known limit: mlx_lm.server has no memory preflight — an oversized
          load fails at Metal's wired ceiling (contained per-request error)
          instead of being politely queued/refused. The tracked upgrade is
          vllm-mlx's models-config manager (memory_budget_gb +
          wait_then_preempt) growing a dynamic HF-cache mode — see the
          bump-check note on the vllmMlx pin in lib/versions.nix.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 11435;
        description = "Port for the dynamic-tier mlx_lm.server (bound to programs.mlx.host).";
      };
    };

    # enableMetrics — Native Prometheus metrics endpoint (--enable-metrics).
    # Exposes /metrics on each worker for scrape-based monitoring (Cribl Edge
    # has a built-in Prometheus input). No custom collectors required.
    enableMetrics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the native Prometheus /metrics endpoint on each vllm-mlx worker (--enable-metrics).";
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
