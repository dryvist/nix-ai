{
  config,
  lib,
  pkgs,
  ...
}:
#
# MLX Inference Server Module (vllm-mlx 0.2.9 + llama-swap proxy)
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
# Parameter reference: vllm-mlx 0.2.9 `serve --help` output (captured from local binary).
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
  vllmMlxVersion = versions.vllmMlx;
  parakeetMlxVersion = versions.parakeetMlx;
  mlxVlmVersion = versions.mlxVlm;

  # Central vllm-mlx wrapper — single source of truth for the pinned version.
  # The LaunchAgent needs a Nix store path (not a PATH lookup), so the
  # derivation lives here. Also added to home.packages for CLI access.
  #
  # mlx==0.31.1 + mlx-lm==0.31.2 are pinned together because mlx 0.31.2 changed
  # cross-thread stream registration semantics: generation_stream (created at
  # mlx_lm module import in the main thread) is no longer visible to vllm-mlx's
  # scheduler thread, causing "There is no Stream(gpu, N) in current thread" on
  # every inference call. mlx_lm 0.31.3 was released alongside mlx 0.31.2, so
  # both are rolled back together. See nix-ai#751.
  mlxPin = "mlx==${versions.mlx}";
  mlxLmPin = "mlx-lm==${versions.mlxLm}";
  vllmMlxPkg = pkgs.writeShellScriptBin "vllm-mlx" ''
    exec ${pkgs.uv}/bin/uvx --from "vllm-mlx==${vllmMlxVersion}" --with "${mlxPin}" --with "${mlxLmPin}" vllm-mlx "$@"
  '';

  # llama-swap proxy package — sits on the API port, manages vllm-mlx child processes.
  llamaSwapPkg = pkgs.llama-swap;

  apiUrl = "http://${cfg.host}:${toString cfg.port}/v1";
  launchAgentLabel = "dev.vllm-mlx.server";

  # Mutable runtime config path — llama-swap reads this with --watch-config.
  # mlx-discover merges auto-discovered models into this file at runtime.
  # The Nix-generated llamaSwapConfigFile seeds this on first activation.
  llamaSwapRuntimeConfigPath = "${config.home.homeDirectory}/.config/mlx/llama-swap.json";

  # Build the vllm-mlx serve command string for a given model ID.
  # NOTE: \${PORT} is a llama-swap template macro — must be escaped to prevent
  # Nix string interpolation from consuming it before the config is written.
  mkVllmCmd =
    modelId:
    let
      baseCmd = "${lib.getExe vllmMlxPkg} serve ${modelId} --port \${PORT} --host ${cfg.host}";
      flags = lib.concatStringsSep " " (
        lib.optionals (cfg.cacheMemoryMb != null) [
          "--cache-memory-mb"
          (toString cfg.cacheMemoryMb)
        ]
        ++ lib.optionals (cfg.prefillBatchSize != null) [
          "--prefill-batch-size"
          (toString cfg.prefillBatchSize)
        ]
        ++ lib.optionals cfg.continuousBatching [ "--continuous-batching" ]
        ++ lib.optionals cfg.enablePrefixCaching [ "--enable-prefix-cache" ]
        ++ lib.optionals cfg.pagedKvCache [ "--use-paged-cache" ]
        ++ lib.optionals (cfg.maxNumSeqs != null) [
          "--max-num-seqs"
          (toString cfg.maxNumSeqs)
        ]
        ++ lib.optionals (cfg.chunkedPrefillTokens != null) [
          "--chunked-prefill-tokens"
          (toString cfg.chunkedPrefillTokens)
        ]
        ++ lib.optionals (cfg.completionBatchSize != null) [
          "--completion-batch-size"
          (toString cfg.completionBatchSize)
        ]
        ++ lib.optionals (cfg.maxTokens != null) [
          "--max-tokens"
          (toString cfg.maxTokens)
        ]
        ++ lib.optionals cfg.enableAutoToolChoice [ "--enable-auto-tool-choice" ]
        ++ lib.optionals (cfg.enableAutoToolChoice && cfg.toolCallParser != null) [
          "--tool-call-parser"
          cfg.toolCallParser
        ]
        ++ lib.optionals (cfg.reasoningParser != null) [
          "--reasoning-parser"
          cfg.reasoningParser
        ]
      );
    in
    "${baseCmd}${lib.optionalString (flags != "") " ${flags}"}";

  # Role registry (services.aiStack.models): role-name -> physical model ID.
  # Single source of truth.
  roleModels = config.services.aiStack.models;

  # Group roles by physical model. One backend serves many role aliases.
  rolesByPhysical = lib.groupBy (role: roleModels.${role}) (lib.attrNames roleModels);

  # One entry per unique physical model. The entry owning the "default"
  # alias is preloaded; others inherit the proxy idle TTL.
  #
  # useModelName makes llama-swap rewrite the OpenAI-compatible request body's
  # `model` field to the physical model id before forwarding to vllm-mlx.
  # vllm-mlx 0.2.9 strictly validates the model field against the loaded model
  # name and returns 404 for unknown names — without this rewrite, callers
  # using a capability-class alias (e.g. `model: "default"`) hit
  #   "The model `default` does not exist."
  # even though llama-swap routed the request correctly. With it, the alias
  # works end-to-end through the local proxy without needing Bifrost in front.
  registryModels = lib.mapAttrs (physical: roles: {
    cmd = mkVllmCmd physical;
    ttl = if builtins.elem "default" roles then 0 else cfg.proxy.idleTtl;
    env = [ "HF_HOME=${cfg.huggingFaceHome}" ];
    checkEndpoint = "/v1/models";
    aliases = roles;
    useModelName = physical;
  }) rolesByPhysical;

  # Additional ad-hoc models from cfg.models (existing extension point).
  additionalModels = lib.mapAttrs (
    name: modelCfg:
    {
      cmd =
        mkVllmCmd name
        + lib.optionalString (modelCfg.extraArgs != [ ]) (
          " " + lib.concatStringsSep " " modelCfg.extraArgs
        );
      ttl = if modelCfg.ttl > 0 then modelCfg.ttl else cfg.proxy.idleTtl;
      env = [ "HF_HOME=${cfg.huggingFaceHome}" ];
      checkEndpoint = "/v1/models";
    }
    // lib.optionalAttrs (modelCfg.aliases != [ ]) {
      inherit (modelCfg) aliases;
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
      swap = true;
      exclusive = true;
      members = builtins.attrNames allModels;
    };

    # Preload by role, not physical name. llama-swap resolves "default"
    # via the alias table on the registryModels entry.
    hooks.on_startup.preload = [ "default" ];
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
