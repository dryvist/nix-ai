#
# MLX Module — Runtime safety + model-swap proxy options
#
# MEMORY SAFETY (layers, furthest-from-OS trips first):
#   L3 serving budget — model weights + prompt-cache + retained buffer cache.
#   L2 process cap     — memoryHardLimitGb, enforced in-process by the mlx_lm
#                        launcher (mx.set_memory_limit / mx.set_cache_limit;
#                        see modules/mlx/scripts/mlx-lm-launch.py).
#   L1 OS wired ceiling — host iogpu.wired_limit_mb (nix-darwin tunables).
# Official mlx_lm additionally receives a prompt-cache byte limit. launchd
# HardResourceLimits is absent: it would cap llama-swap, not its model-server
# children. gpuMemoryUtilization and autoUnloadIdleSeconds apply to the
# preserved vllm-mlx backend only and are inert under mlx-lm.
#
# MODEL SWITCHING (llama-swap proxy):
# llama-swap sits on the API port and manages the official mlx_lm.server as
# child processes. Model switching is transparent: send a request with
# model: "X" and the proxy handles it.
#
{ lib, ... }:
{
  options.programs.mlx = {
    enabledBackends = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "mlx-lm"
          "vllm-mlx"
        ]
      );
      default = [ "mlx-lm" ];
      description = "Serving implementations permitted to run. Official mlx-lm is enabled; preserved vllm-mlx support remains disabled unless explicitly listed.";
    };

    singleModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "mlx-community/<the-one-model-to-serve>";
      description = ''
        Single-model mode: physical model id (must be a key of the compiled
        models registry) that becomes the ONLY servable model, resident with
        ttl=0. Every alias — every logical role AND every other model's own
        physical id — routes to it, so any caller naming any known model
        gets this one. Every other compiled model/group is preserved but
        emitted under disabledModels/disabledGroups instead of
        models/groups (llama-swap ignores those keys); move an entry back
        under models to re-enable it. null (default) serves the full
        multi-model registry as normal.
      '';
    };

    modelServerBackend = lib.mkOption {
      type = lib.types.enum [
        "mlx-lm"
        "vllm-mlx"
      ];
      default = "mlx-lm";
      description = "Implementation used by every standalone MLX model server. The selected value must also be present in enabledBackends.";
    };

    memoryHardLimitGb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 99;
      description = ''
        L2 process memory limit in GiB, enforced in-process before serving via
        mx.set_memory_limit in the mlx_lm launcher (scripts/mlx-lm-launch.py).
        A guideline in MLX terms — it forces cache shedding and allocation
        failure ahead of the host wired ceiling (L1, iogpu.wired_limit_mb)
        rather than at MLX's 1.5x-working-set default, so memory pressure
        surfaces as an application error instead of host-wide swap. Set below
        the wired ceiling with a small cushion (99 GiB under the 100 GiB /
        102400 MiB ceiling on the 128 GiB Macs).
      '';
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
        launchd ProcessType for the llama-swap proxy and model-server
        children. Background makes the tree Jetsam-eligible but its QoS clamp
        throttles Metal decode roughly 8x (11 -> 87 tok/s measured 2026-06-09
        on an M4 Max). Interactive restores full GPU performance. Memory
        protection comes from the host wired-memory ceiling and the selected
        backend's cache limits.
      '';
    };

    # Backend-neutral worker verbosity. Official mlx_lm receives its native
    # --log-level flag; preserved vllm-mlx receives the patched
    # VLLM_MLX_LOG_LEVEL environment variable.
    serverLogLevel = lib.mkOption {
      type = lib.types.enum [
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
      description = ''
        MLX model-server verbosity. Official mlx_lm receives --log-level;
        preserved vllm-mlx receives the locally patched VLLM_MLX_LOG_LEVEL
        environment variable. "debug" is the production default for the
        private observability pipeline and includes request and response
        content. Set to "info" to omit normal request and response bodies.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional arguments for the selected MLX model server";
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

    # modelExtraArgs — extra selected-server arguments for REGISTRY models, keyed by
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
      description = "Additional selected-server arguments per physical registry model id, appended after the global flags.";
    };

    # modelConcurrencyLimits — per-physical-id override of the GLOBAL proxy
    # concurrencyLimit (the llama-swap-side in-flight cap). modelExtraArgs and
    # modelFlagOverrides tune the selected worker; this one tunes the proxy gate
    # in front of it. Needed for models that abort under parallel dispatch
    # regardless of worker batch width — e.g. Qwen3-Next-80B (metal::malloc
    # resource limit under concurrent requests), which must be serialized to 1.
    # Keyed by physical model id; absent id falls back to proxy.concurrencyLimit.
    modelConcurrencyLimits = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.positive;
      default = { };
      example = lib.literalExpression ''
        {
          "mlx-community/<crash-under-concurrency-model>" = 1;
        }
      '';
      description = "Per-physical-model override of programs.mlx.proxy.concurrencyLimit (llama-swap in-flight cap), for models that must be serialized independent of the global default.";
    };

    # Per-physical-id llama-swap lifecycle for role-registry models. This is
    # backend-neutral: unlike vllm-mlx's worker-side auto-unload flag, the
    # proxy TTL also unloads official mlx_lm workers.
    modelTtls = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      default = { };
      description = "Per-physical-model llama-swap idle TTL. Absent models inherit programs.mlx.proxy.idleTtl.";
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
  };
}
