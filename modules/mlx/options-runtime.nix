#
# MLX Module — Runtime safety + model-swap proxy options
#
# OOM PREVENTION (2026-03-21 incident: 171.9 GB on 128 GB RAM):
# ProcessType=Background makes vllm-mlx Jetsam-eligible; HardResourceLimits
# sets a kernel-enforced RSS ceiling. KeepAlive auto-restarts after Jetsam kill.
#
# MODEL SWITCHING (llama-swap proxy):
# llama-swap sits on the API port and manages vllm-mlx backends as child
# processes. Model switching is transparent: send a request with model: "X"
# and the proxy handles it.
#
{ lib, ... }:
{
  options.programs.mlx = {
    memoryHardLimitGb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Hard RSS limit in GB. Kernel kills process above this. Leaves 28GB for OS + apps on 128GB systems.";
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional vllm-mlx serve arguments for this model";
            };
            ttl = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 0;
              description = "Seconds of idle time before unloading. 0 = use proxy.idleTtl default.";
            };
            aliases = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Alternative model names that route to this model";
            };
          };
        }
      );
      default = { };
      description = "Additional models available for on-demand switching via llama-swap proxy. The defaultModel is always available with TTL 0.";
    };

    proxy = {
      healthCheckTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 180;
        description = "Seconds to wait for a backend to become healthy. 70GB models take 20-60s to load; 180s covers the worst case.";
      };
      idleTtl = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 1800;
        description = "Default idle TTL in seconds for non-default models. 0 = never auto-unload. Default 30 min.";
      };
      logLevel = lib.mkOption {
        type = lib.types.enum [
          "debug"
          "info"
          "warn"
          "error"
        ];
        default = "info";
        description = ''
          llama-swap log verbosity. "info" is the production default — keeps
          model load events and swap transitions visible without dumping every
          weight tensor name. Switch to "debug" only when actively diagnosing
          proxy behaviour (logs every proxied HTTP request/response body and
          makes `curl http://127.0.0.1:11434/logs/stream` a live I/O tap).
          Note: debug output rotates within the 10 MB LaunchAgent log limit.
        '';
      };
      logToStdout = lib.mkOption {
        type = lib.types.enum [
          "proxy"
          "upstream"
          "both"
          "none"
        ];
        default = "both";
        description = ''
          Which output streams llama-swap forwards to stdout (and therefore
          the /logs/stream SSE endpoint). "both" interleaves proxy request
          logs with vllm-mlx upstream output. "proxy" (default upstream
          behaviour) shows only proxy-level events.
        '';
      };
    };
  };
}
