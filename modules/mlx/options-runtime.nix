#
# MLX Module — Runtime safety + model-swap proxy options
#
# OOM PREVENTION (2026-03-21 incident: 171.9 GB on 128 GB RAM):
# HardResourceLimits sets a kernel-enforced RSS ceiling; KeepAlive auto-restarts
# after a kill. ProcessType=Background was originally part of this mitigation
# (Jetsam eligibility), but Background QoS clamps Metal GPU work ~8x on Apple
# Silicon — measured 11 -> 87 tok/s decode on the same model when switching to
# Interactive (2026-06-09). The RSS hard limit alone is the OOM backstop now;
# see the processType option below.
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

    processType = lib.mkOption {
      type = lib.types.enum [
        "Background"
        "Standard"
        "Adaptive"
        "Interactive"
      ];
      default = "Interactive";
      description = ''
        launchd ProcessType for the llama-swap proxy (inherited by vllm-mlx
        children). Background makes the tree Jetsam-eligible but its QoS clamp
        throttles Metal decode roughly 8x (11 -> 87 tok/s measured 2026-06-09
        on an M4 Max). Interactive restores full GPU performance; OOM
        protection remains via memoryHardLimitGb (HardResourceLimits) and
        KeepAlive restart. Set back to Background only if Jetsam eligibility
        matters more than inference speed.
      '';
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
            filters = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = ''
                Per-model llama-swap filters. Merged on top of
                programs.mlx.proxy.defaultFilters, so this model entry can
                tighten, loosen, or fully replace the global filter.
                See modules/mlx/options-filters.nix for the schema.
              '';
            };
          };
        }
      );
      default = { };
      description = "Additional models available for on-demand switching via llama-swap proxy. All models (including the default-aliased one) share the uniform proxy.idleTtl unless overridden per-model.";
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
        description = "Idle TTL in seconds applied uniformly to every model in the registry (including the default-aliased one). 0 = never auto-unload (escape hatch). Default 1800 s (30 min) — a bounded warm window. Tightened from the prior 3600 s default after the recurring `nix-ai#801` stuck-past-TTL family of incidents; shorter windows mean less time exposed when the upstream `llama-swap` race fires during unload.";
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
      concurrencyLimit = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = ''
          Max in-flight requests llama-swap will forward to vllm-mlx per
          model. Maps directly to the YAML key llama-swap reads
          (`concurrencyLimit`); excess requests get HTTP 429.

          Default 2 — serializes bursts so a multi-pipe / multi-tool storm
          can't fan out parallel calls that pile on faster than vllm-mlx
          can schedule. Tightened from the prior 4 after the 2026-05-29
          → 2026-06-03 pipe-timeout storm where bursts of concurrent
          callers saturated the disconnect_guard window. The 2026-05-15
          finish_reason:error incident remains tracked separately as a
          vllm-mlx scheduler bug.

          The trade-off: a value below `maxNumSeqs` slightly under-utilizes
          continuous batching (1.5x–3x throughput peak). On this host the
          stability win dominates. Bump only if you observe sustained
          queue depth at the proxy without thrash.

          Setting this to 1 silently defeats continuous batching.
        '';
      };
    };
  };
}
