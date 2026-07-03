{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  ...
}:
#
# MLX Inference Server Module (vllm-mlx, pinned in lib/versions.nix, + llama-swap proxy)
#
# Manages the MLX inference stack as a macOS LaunchAgent for Apple Silicon.
# MLX is ~2x faster than llama.cpp for token generation on M4 Max with ~50% less memory.
#
# Architecture:
#   - llama-swap proxy listens on the API port (11434) and manages vllm-mlx backends
#   - vllm-mlx child processes start on ephemeral ports (11436+)
#   - Model switching is transparent: send model: "X" and the proxy handles the swap
#   - Default model is preloaded at startup; additional models load on demand
#
# Features:
#   - Always-on LaunchAgent with llama-swap proxy managing vllm-mlx backends
#   - Transparent model switching (no process management required)
#   - CLI tools for quick prompts (mlx) and interactive chat (mlx-chat)
#   - Benchmark suite: throughput (mlx-bench), engine (mlx-bench-engine),
#     raw MLX (mlx-bench-raw), accuracy evaluation (mlx-eval)
#   - OpenAI-compatible API at http://127.0.0.1:11434/v1
#
# Models stored on dedicated APFS volume: /Volumes/HuggingFace
#
# Parameter reference: vllm-mlx 0.4.0 `serve --help` output (captured from local binary).
#
let
  cfg = config.programs.mlx;
  versions = import ../../lib/versions.nix;

  # Version history for vllm-mlx (canonical pin in lib/versions.nix):
  #   - 0.2.6: stable baseline.
  #   - 0.2.7: regressed vllm_mlx/utils/tokenizer.py::load_model_with_fallback
  #     (the success path forgot to return, yielding None implicitly).
  #   - 0.2.8: fixed that regression but mis-detected Qwen3.5 as MLLM and its
  #     MLLM continuous-batching path failed parallel text requests.
  #   - 0.2.9: ships Paged KV Cache + prefix sharing + continuous batching
  #     (MLLM-detection bug fixed). Loads gemma-4-e4b architectures.
  #   - 0.3.0: stable baseline after the 0.2.x line.
  #   - 0.4.0: GPT-OSS/harmony prompt rendering for tool calls (required to
  #     serve gpt-oss models with working tool calling); parser roster grows
  #     to 17 tool + 7 reasoning parsers; requires mlx-lm>=0.31.3.
  vllmMlxVersion = versions.vllmMlx;
  parakeetMlxVersion = versions.parakeetMlx;
  mlxVlmVersion = versions.mlxVlm;

  # Central vllm-mlx wrapper — single source of truth for the pinned version.
  # The LaunchAgent needs a Nix store path (not a PATH lookup), so the
  # derivation lives here. Also added to home.packages for CLI access.
  #
  # mlx + mlx-lm are pinned together as a lockstep pair (see lib/versions.nix).
  # History: mlx 0.31.2 originally broke vllm-mlx 0.2.9's scheduler thread
  # ("There is no Stream(gpu, N) in current thread", nix-ai#751); vllm-mlx
  # 0.4.0 is built against mlx 0.31.2 / mlx-lm 0.31.3 and the crash no longer
  # reproduces under concurrent continuous batching (validated 2026-07-02).
  mlxPin = "mlx==${versions.mlx}";
  mlxLmPin = "mlx-lm==${versions.mlxLm}";
  vllmMlxPkg = pkgs.writeShellScriptBin "vllm-mlx" ''
    exec ${pkgs.uv}/bin/uvx --from "vllm-mlx==${vllmMlxVersion}" --with "${mlxPin}" --with "${mlxLmPin}" vllm-mlx "$@"
  '';

  # llama-swap proxy package — sits on the API port, manages vllm-mlx child processes.
  # Sourced from nixpkgs-unstable: 25.11-darwin froze it at v165 on 2025-09-22
  # with no backports while unstable kept moving (currently v211). See nix-ai#801.
  llamaSwapPkg = nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.llama-swap;

  apiUrl = "http://${cfg.host}:${toString cfg.port}/v1";
  launchAgentLabel = "dev.vllm-mlx.server";

  # Mutable runtime config path — llama-swap reads this with --watch-config.
  # mlx-discover merges auto-discovered models into this file at runtime.
  # The Nix-generated llamaSwapConfigFile seeds this on first activation.
  llamaSwapRuntimeConfigPath = "${config.home.homeDirectory}/.config/mlx/llama-swap.json";

  # Build the vllm-mlx serve command string for a given model ID.
  # Global option values may be replaced per physical model via
  # modelFlagOverrides; every override key must name an existing programs.mlx
  # option so a typo fails the eval instead of silently keeping the global.
  # NOTE: \${PORT} is a llama-swap template macro — must be escaped to prevent
  # Nix string interpolation from consuming it before the config is written.
  mkVllmCmd =
    modelId:
    let
      overrides = cfg.modelFlagOverrides.${modelId} or { };
      unknown = lib.filter (k: !(cfg ? ${k})) (lib.attrNames overrides);
      c =
        if unknown == [ ] then
          cfg // overrides
        else
          throw "programs.mlx.modelFlagOverrides.\"${modelId}\": unknown option name(s): ${lib.concatStringsSep ", " unknown}";
      baseCmd = "${lib.getExe vllmMlxPkg} serve ${modelId} --port \${PORT} --host ${c.host}";
      flags = lib.concatStringsSep " " (
        lib.optionals (c.cacheMemoryMb != null) [
          "--cache-memory-mb"
          (toString c.cacheMemoryMb)
        ]
        ++ lib.optionals (c.prefillBatchSize != null) [
          "--prefill-batch-size"
          (toString c.prefillBatchSize)
        ]
        ++ lib.optionals (c.gpuMemoryUtilization != null) [
          "--gpu-memory-utilization"
          (toString c.gpuMemoryUtilization)
        ]
        ++ lib.optionals (c.autoUnloadIdleSeconds != 0) [
          "--auto-unload-idle-seconds"
          (toString c.autoUnloadIdleSeconds)
        ]
        ++ lib.optionals c.enableMetrics [ "--enable-metrics" ]
        ++ lib.optionals c.continuousBatching [ "--continuous-batching" ]
        ++ lib.optionals c.enablePrefixCaching [ "--enable-prefix-cache" ]
        ++ lib.optionals c.pagedKvCache [ "--use-paged-cache" ]
        ++ lib.optionals (c.maxNumSeqs != null) [
          "--max-num-seqs"
          (toString c.maxNumSeqs)
        ]
        ++ lib.optionals (c.chunkedPrefillTokens != null) [
          "--chunked-prefill-tokens"
          (toString c.chunkedPrefillTokens)
        ]
        ++ lib.optionals (c.completionBatchSize != null) [
          "--completion-batch-size"
          (toString c.completionBatchSize)
        ]
        ++ lib.optionals (c.maxTokens != null) [
          "--max-tokens"
          (toString c.maxTokens)
        ]
        ++ lib.optionals (c.maxRequestTokens != null) [
          "--max-request-tokens"
          (toString c.maxRequestTokens)
        ]
        ++ lib.optionals c.enableAutoToolChoice [ "--enable-auto-tool-choice" ]
        ++ lib.optionals (c.enableAutoToolChoice && c.toolCallParser != null) [
          "--tool-call-parser"
          c.toolCallParser
        ]
        ++ lib.optionals (c.reasoningParser != null) [
          "--reasoning-parser"
          c.reasoningParser
        ]
      );
    in
    "${baseCmd}${lib.optionalString (flags != "") " ${flags}"}";

  # Role registry (services.aiStack.models): role-name -> physical model ID.
  # Single source of truth.
  roleModels = config.services.aiStack.models;

  # Group roles by physical model. One backend serves many role aliases.
  rolesByPhysical = lib.groupBy (role: roleModels.${role}) (lib.attrNames roleModels);

  # One entry per unique physical model. Every model — including the entry
  # owning the "default" alias — inherits the uniform proxy idle TTL.
  # The default model is still preloaded on startup via hooks.on_startup.preload
  # below, so the first request never pays a cold-start cost; after one hour
  # of idle it unloads and the next request reloads it (~15-30 s).
  #
  # useModelName makes llama-swap rewrite the OpenAI-compatible request body's
  # `model` field to the physical model id before forwarding to vllm-mlx.
  # vllm-mlx 0.2.9 strictly validates the model field against the loaded model
  # name and returns 404 for unknown names — without this rewrite, callers
  # using a capability-class alias (e.g. `model: "default"`) hit
  #   "The model `default` does not exist."
  # even though llama-swap routed the request correctly. With it, the alias
  # works end-to-end through the local proxy.
  # Default llama-swap filters applied to every model in the registry.
  # See modules/mlx/options-filters.nix for the schema and reasoning.
  # Filters run at the proxy layer BEFORE the request hits vllm-mlx, so they
  # apply universally to every caller, every prompt, every model — including
  # callers that explicitly send greedy-decoding parameters (setParams
  # overrides client values per llama-swap's documented semantics).
  inherit (cfg.proxy) defaultFilters;

  registryModels = lib.mapAttrs (
    physical: roles:
    let
      extraArgs = cfg.modelExtraArgs.${physical} or [ ];
    in
    {
      cmd =
        mkVllmCmd physical + lib.optionalString (extraArgs != [ ]) (" " + lib.escapeShellArgs extraArgs);
      ttl = cfg.proxy.idleTtl;
      env = [ "HF_HOME=${cfg.huggingFaceHome}" ];
      checkEndpoint = "/v1/models";
      aliases = roles;
      useModelName = physical;
      inherit (cfg.proxy) concurrencyLimit;
    }
    // lib.optionalAttrs (defaultFilters != { }) {
      filters = defaultFilters;
    }
  ) rolesByPhysical;

  # Additional ad-hoc models from cfg.models (existing extension point).
  # Per-model filters merge on top of the global default so an individual
  # model can tighten one key without dropping siblings — e.g. setting
  # cfg.models.foo.filters.setParams.top_p preserves the global
  # frequency_penalty / presence_penalty defaults. Uses lib.recursiveUpdate
  # so nested attrsets (setParams, future filter groups) merge key-by-key
  # rather than wholesale-replacing each other.
  additionalModels = lib.mapAttrs (
    name: modelCfg:
    let
      mergedFilters = lib.recursiveUpdate defaultFilters (modelCfg.filters or { });
    in
    {
      cmd =
        mkVllmCmd name
        + lib.optionalString (modelCfg.extraArgs != [ ]) (
          " " + lib.concatStringsSep " " modelCfg.extraArgs
        );
      ttl = if modelCfg.ttl > 0 then modelCfg.ttl else cfg.proxy.idleTtl;
      env = [ "HF_HOME=${cfg.huggingFaceHome}" ];
      checkEndpoint = "/v1/models";
      inherit (cfg.proxy) concurrencyLimit;
    }
    // lib.optionalAttrs (modelCfg.aliases != [ ]) {
      inherit (modelCfg) aliases;
    }
    // lib.optionalAttrs (mergedFilters != { }) {
      filters = mergedFilters;
    }
  ) cfg.models;

  allModels = registryModels // additionalModels;

  llamaSwapConfigAttrs = {
    inherit (cfg.proxy) healthCheckTimeout logLevel logToStdout;
    # logLevel="debug" logs every proxied HTTP request/response body.
    # logToStdout="both" merges proxy and vllm-mlx output into one stream.
    # Tap live I/O with: curl http://127.0.0.1:11434/logs/stream
    # Configurable via programs.mlx.proxy.logLevel / logToStdout.
    startPort = 11436;

    models = allModels;

    groups.mlx-models = {
      swap = cfg.proxy.groupSwap;
      exclusive = true;
      members = builtins.attrNames allModels;
    };

    # Preload by role, not physical name. llama-swap resolves "default"
    # via the alias table on the registryModels entry.
    hooks.on_startup.preload = cfg.preload;
  };

  # Use pkgs.writeText (not builtins.toFile) because content references store paths
  # (vllmMlxPkg store path is embedded in the cmd strings).
  llamaSwapConfigFile = pkgs.writeText "llama-swap-config.json" (
    builtins.toJSON llamaSwapConfigAttrs
  );
in
{
  imports = [
    ./options-server.nix
    ./options-cache.nix
    ./options-batching.nix
    ./options-filters.nix
    ./options-parsers.nix
    ./options-runtime.nix
    ./packages.nix
    ./launchd.nix
  ];

  # Pass shared bindings to sub-modules via _module.args
  _module.args.mlxShared = {
    inherit
      cfg
      vllmMlxPkg
      vllmMlxVersion
      parakeetMlxVersion
      mlxVlmVersion
      apiUrl
      launchAgentLabel
      llamaSwapPkg
      llamaSwapConfigFile
      llamaSwapConfigAttrs
      llamaSwapRuntimeConfigPath
      ;
  };

  # Enforce documented option dependencies. Without these, vllm-mlx silently
  # mis-behaves when consumers flip one boolean and forget the partner.
  assertions = lib.optionals cfg.enable [
    {
      assertion = !cfg.enablePrefixCaching || cfg.pagedKvCache;
      message = ''
        programs.mlx.enablePrefixCaching requires programs.mlx.pagedKvCache to
        also be true. vllm-mlx 0.2.9 builds the prefix-sharing index inside
        the paged KV cache; turning prefix caching on without paged KV cache
        either fails to start or silently drops the prefix-share path.
        Either set both to true (the defaults) or both to false.
      '';
    }
  ];
}
