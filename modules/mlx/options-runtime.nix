#
# MLX Module — Runtime safety + model-swap proxy options
#
# OOM PREVENTION:
# The enforced per-worker memory bound is programs.mlx.gpuMemoryUtilization
# (options-cache.nix) — a Metal allocation ceiling applied inside each
# vllm-mlx worker, where the memory actually lives. launchd
# HardResourceLimits is NOT serialized into the plist: it would only cap the
# llama-swap proxy, and macOS does not reliably enforce RSS rlimits (see
# launchd.nix). memoryHardLimitGb below is therefore declarative intent, not
# an enforced kernel limit. autoUnloadIdleSeconds adds a worker-side idle
# failsafe. ProcessType=Background was once part of the mitigation (Jetsam
# eligibility) but its QoS clamp throttles Metal decode ~8x — see the
# processType option below.
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
      description = "Declared RSS budget in GB for the LLM stack (documentation/dashboards). NOT kernel-enforced: launchd HardResourceLimits would only cap the proxy process and macOS does not reliably enforce RSS rlimits. The enforced per-worker bound is gpuMemoryUtilization.";
    };

    # autoUnloadIdleSeconds — Worker-side idle self-unload (--auto-unload-idle-seconds).
    # Defense in depth alongside llama-swap's proxy.idleTtl: the worker frees its
    # own model weights after this many idle seconds even if the proxy loses
    # track of it (upstream lifecycle race, see nix-ai#801). Keep LONGER than
    # proxy.idleTtl so the proxy remains the primary eviction path.
    autoUnloadIdleSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1800;
      description = "Worker self-unloads its model after this many idle seconds (vllm-mlx --auto-unload-idle-seconds). 0 = disabled. Keep greater than proxy.idleTtl; this is the failsafe when the proxy cannot evict.";
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
        protection comes from gpuMemoryUtilization (per-worker Metal ceiling)
        and KeepAlive restart. Set back to Background only if Jetsam
        eligibility matters more than inference speed.
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
      description = "Additional non-resident models available for on-demand switching via llama-swap proxy. These form the swap tier; they are loaded only when requested and can carry their own TTLs, aliases, filters, and serve-flag overrides.";
    };

    # modelExtraArgs — extra vllm-mlx serve args for REGISTRY models, keyed by
    # physical model id. The role registry (services.aiStack.models) builds one
    # backend per unique physical model with uniform global flags; this is the
    # per-backend escape hatch when flags genuinely differ per model —
    # e.g. a host serving gpt-oss (--tool-call-parser harmony) alongside a
    # Qwen coder (--tool-call-parser qwen3_coder) sets the global
    # toolCallParser to null and pins one parser per physical id here.
    # (cfg.models.*.extraArgs already covers ad-hoc non-registry models.)
    modelExtraArgs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = lib.literalExpression ''
        {
          "mlx-community/<large-model>" = [
            "--tool-call-parser"
            "harmony"
          ];
        }
      '';
      description = "Additional vllm-mlx serve arguments per physical registry model id, appended after the global flags.";
    };

    # modelFlagOverrides — per-physical-id overrides of the GLOBAL serve
    # options. modelExtraArgs can only APPEND flags; it cannot retract a
    # default-on boolean like pagedKvCache, whose --use-paged-cache flag has
    # no CLI negation. Keys must name serve options the command builder
    # actually reads (the list in modules/mlx/default.nix mkVllmCmd) — any
    # other key fails the eval instead of silently keeping the global value.
    # Motivating case (vllm-mlx 0.4.0): the paged KV cache is incompatible
    # with gpt-oss's alternating sliding-window attention — generation fails
    # with "[broadcast_shapes] Shapes (1,8,64,64) and (1,8,115,64) cannot be
    # broadcast" (paged-cache block size 64 vs. prompt length). Disabling
    # pagedKvCache + enablePrefixCaching on that one model fixes it; sibling
    # models keep prefix caching.
    modelFlagOverrides = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.raw);
      default = { };
      example = lib.literalExpression ''
        {
          "mlx-community/<sliding-window-model>" = {
            pagedKvCache = false;
            enablePrefixCaching = false;
          };
        }
      '';
      description = "Per-physical-model overrides of programs.mlx serve options (e.g. pagedKvCache, enablePrefixCaching), merged over the global values when building that model's vllm-mlx command.";
    };

    # preload — models the warmup agent (mlx-warmup.py, via
    # MLX_PRELOAD_MODELS_JSON) faults in after every proxy (re)start, so the
    # first request never pays a cold start. Deliberately NOT emitted as
    # llama-swap hooks.on_startup.preload — that hook's request shape 404s
    # vllm-mlx and llama-swap stops the worker on preload failure (#1175).
    # Multi-resident hosts list every role they keep warm, e.g.
    # [ "default" "coding" ]; each extra entry costs its full weight footprint
    # until the idle TTL evicts it.
    preload = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "default" ];
      description = "Resident models (role aliases or physical ids) the warmup agent loads after proxy start. Every entry occupies memory concurrently until its idle TTL — size the list against the host's wired-memory budget. Swap-tier models belong in programs.mlx.models instead.";
    };

    proxy = {
      # groupSwap — llama-swap `groups.mlx-models.swap`. true (default) keeps
      # the one-resident-model posture: loading any model evicts the previous
      # one, so swap-thrash is impossible on RAM-constrained workstations.
      # false lets multiple registry models stay resident concurrently
      # (server-class hosts serving e.g. a large default plus a coder model);
      # the memory bound then falls to gpuMemoryUtilization/cacheMemoryMb per
      # worker, which the host must size so the sum of resident workers fits
      # its wired-memory budget.
      groupSwap = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether llama-swap unloads the resident model before loading another (groups.mlx-models.swap). Set false on hosts with the memory headroom to keep several models resident at once.";
      };

      healthCheckTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 180;
        description = "Seconds to wait for a backend to become healthy. 70GB models take 20-60s to load; 180s covers the worst case.";
      };
      idleTtl = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 900;
        description = "Idle TTL in seconds applied uniformly to every model in the registry (including the default-aliased one). 0 = never auto-unload (escape hatch). Default 900 s (15 min). Tightened twice: 3600 -> 1800 after the recurring `nix-ai#801` stuck-past-TTL incidents, then 1800 -> 900 after the 2026-06-10 nix-mac-performance RC14 snapshot showed a single healthy in-TTL ~50 GB worker plus the desktop working set saturating compressor + swap on a 128 GB host — idle-weight dwell is the dominant memory cost, and a 4-bit MoE model reloads from NVMe in 10-20 s, so eviction is cheap relative to the host-wide paging it prevents.";
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

          Default 4 — matches `maxNumSeqs` so continuous batching is fed.
          Re-raised from 2 on 2026-07-11 after a replicated c1-c8 sweep
          (MBP Coder-30B): zero errors within the limit, 1.6-2.3x
          aggregate when the batcher engages, worst case serialization
          (~1.0x). Scheduling is bimodal, so treat >1x as opportunistic
          and keep bench drivers pinned to their documented concurrency
          (mlx-benchmarks RUNBOOK). The pipe-timeout storm behind the old
          4->2 tightening predated the maxRequestTokens hardening that
          fixed its cause. Above the limit callers get 429 — cap or
          retry with backoff; the llm_router tier absorbs 429s via its
          retry policy. Setting this to 1 silently defeats batching.
        '';
      };
    };
  };
}
