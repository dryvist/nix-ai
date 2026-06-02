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
        default = 3600;
        description = "Idle TTL in seconds applied uniformly to every model in the registry (including the default-aliased one). 0 = never auto-unload (escape hatch). Default 3600 s (1 hour) gives a long warm window without permanently wiring a model's weights.";
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
        default = 4;
        description = ''
          Max in-flight requests llama-swap will forward to vllm-mlx per
          model. Maps directly to the YAML key llama-swap reads
          (`concurrencyLimit`); excess requests get HTTP 429.

          Default 4 matches `maxNumSeqs = 4` so vllm-mlx continuous batching
          stays fully utilized (1.5x–3x throughput on M4 Max 128 GB per
          upstream benchmarks) while still bounding runaway callers so they
          can't pile on faster than vllm-mlx can schedule. The 2026-05-15
          finish_reason:error incident is tracked separately as a vllm-mlx
          scheduler bug — a proxy-side cap is the safety valve, not the fix.

          Setting this to 1 silently defeats continuous batching and is
          almost never what you want; raise it only if vllm-mlx adds more
          headroom (and bump `maxNumSeqs` in lockstep).
        '';
      };
    };

    watchdog = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Periodic watchdog (LaunchAgent + shell script) that kicks the
          vllm-mlx LaunchAgent when worker memory pressure crosses
          thresholds OR a worker sits past its configured TTL by more than
          `ttlGraceMult` ×. Defensive layer against the upstream
          mostlygeek/llama-swap lifecycle race at proxy/process.go:280-289
          (`panic: sync: WaitGroup is reused before previous Wait has
          returned`) — see nix-ai#801 and the docs-starlight architecture
          page at `d/hosts/local-llm-stack`.

          Bug has been observed firing 5+ times on the reference host
          (M4 Max 128 GB). The watchdog acts as defense in depth: even if
          upstream stays broken, the host self-recovers within the
          watchdog's polling interval.
        '';
      };
      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 300;
        description = "How often the watchdog runs (LaunchAgent `StartInterval`). Default 5 min — short enough to catch a stuck worker before it dominates compressor + swap, long enough to avoid spawning chatter at idle.";
      };
      swapThresholdPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 75;
        description = "If `vm.swapusage` used / total exceeds this percentage, the watchdog kicks the LaunchAgent. Default 75 — below the 90 % saturation seen in the 2026-05-19 and 2026-06-02 incidents but well above normal operating headroom.";
      };
      rssThresholdPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 50;
        description = "If any single `vllm-mlx serve` worker's RSS exceeds this percentage of physical RAM, the watchdog kicks. Default 50 — on a 128 GB host that means 64 GB single-process; the 2026-06-02 incident peaked at 55 % (71 GB).";
      };
      ttlGraceMult = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Multiplier applied to a model's configured `ttl` to set the watchdog's stuck-worker threshold. A worker still resident past `ttl * ttlGraceMult` seconds triggers a kick. Default 2 — catches the `nix-ai#801` race fingerprint without false positives during legitimate long-tail inference.";
      };
    };
  };
}
