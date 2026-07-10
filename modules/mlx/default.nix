{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  ...
}:
let
  cfg = config.programs.mlx;
  versions = import ../../lib/versions.nix;

  # vllm-mlx version history and compatibility notes live in lib/versions.nix.
  # This module only keeps the pinning and scheduler-specific glue.
  vllmMlxVersion = versions.vllmMlx;
  parakeetMlxVersion = versions.parakeetMlx;
  mlxVlmVersion = versions.mlxVlm;

  # Central vllm-mlx wrapper — single source of truth for the pinned version.
  # The LaunchAgent needs a Nix store path (not a PATH lookup), so the
  # derivation lives here. Also added to home.packages for CLI access.
  #
  # mlx + mlx-lm are pinned together as a lockstep pair (see lib/versions.nix).
  # Pin mlx and transformers together with vllm-mlx; see lib/versions.nix for
  # the compatibility history behind these versions.
  mlxPin = "mlx==${versions.mlx}";
  mlxLmPin = "mlx-lm==${versions.mlxLm}";
  transformersPin = "transformers==${versions.transformers}";
  vllmMlxPkg = pkgs.writeShellScriptBin "vllm-mlx" ''
    exec ${pkgs.uv}/bin/uvx --from "vllm-mlx==${vllmMlxVersion}" --with "${mlxPin}" --with "${mlxLmPin}" --with "${transformersPin}" vllm-mlx "$@"
  '';
  mlxWarmupPkg = pkgs.writeShellScriptBin "mlx-warmup" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/mlx-warmup.py} "$@"
  '';

  # llama-swap proxy package — sits on the API port, manages vllm-mlx child processes.
  # Sourced from nixpkgs-unstable: 25.11-darwin froze it at v165 on 2025-09-22
  # with no backports while unstable kept moving (currently v211). See nix-ai#801.
  llamaSwapPkg = nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.llama-swap;

  apiUrl = "http://${cfg.host}:${toString cfg.port}/v1";
  launchAgentLabel = "dev.vllm-mlx.server";

  # Shared per-backend env; the buffer-cache cap must ride the env
  # (MLX_BUFFER_CACHE_LIMIT) — rationale in options-cache.nix.
  workerEnv = [
    "HF_HOME=${cfg.huggingFaceHome}"
  ]
  ++ lib.optionals (cfg.bufferCacheLimitGb != null) [
    "MLX_BUFFER_CACHE_LIMIT=${toString (cfg.bufferCacheLimitGb * 1024 * 1024 * 1024)}"
  ];

  # Mutable runtime config path — llama-swap reads this with --watch-config.
  # mlx-discover merges auto-discovered models into this file at runtime.
  # The Nix-generated llamaSwapConfigFile seeds this on first activation.
  llamaSwapRuntimeConfigPath = "${config.home.homeDirectory}/.config/mlx/llama-swap.json";

  # Serve-command builder — split to vllm-cmd.nix (12KB file-size gate).
  inherit (import ./vllm-cmd.nix { inherit lib cfg vllmMlxPkg; }) mkVllmCmd;

  # Role registry (services.aiStack.models): role-name -> physical model ID.
  # Single source of truth.
  roleModels = config.services.aiStack.models;

  # Group roles by physical model. One backend serves many role aliases.
  rolesByPhysical = lib.groupBy (role: roleModels.${role}) (lib.attrNames roleModels);

  # One entry per unique physical model. Every model — including the entry
  # owning the "default" alias — inherits the uniform proxy idle TTL.
  # The default model is still preloaded on startup via hooks.on_startup.preload
  # below, so the first request never pays a cold-start cost; after proxy.idleTtl
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
      env = workerEnv;
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
  # These form the non-resident swap tier. They can be loaded on demand
  # without evicting the resident registry models, and they can carry their
  # own TTLs/aliases/filters.
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
      env = workerEnv;
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

  residentModels = registryModels;
  swapModels = additionalModels;
  allModels = residentModels // swapModels;

  llamaSwapConfigAttrs = {
    inherit (cfg.proxy) healthCheckTimeout logLevel logToStdout;
    # logLevel="debug" logs every proxied HTTP request/response body.
    # logToStdout="both" merges proxy and vllm-mlx output into one stream.
    # Tap live I/O with: curl http://127.0.0.1:11434/logs/stream
    # Configurable via programs.mlx.proxy.logLevel / logToStdout.
    startPort = 11436;

    models = allModels;

    # Merge the two group definitions INSIDE `groups` (disjoint keys), not via
    # an outer `//` on the whole config set. `//` is a shallow update: two
    # sibling `groups.<name>` paths in `a // b` make `b`'s `groups` replace
    # `a`'s wholesale, so the persistent resident group would vanish whenever
    # the swap tier is non-empty — collapsing coder/OptiQ/gpt-oss into
    # llama-swap's implicit swap default and evicting a resident on every
    # cross-model request.
    groups = {
      mlx-models = {
        swap = cfg.proxy.groupSwap;
        exclusive = true;
        persistent = true;
        members = builtins.attrNames residentModels;
      };
    }
    // lib.optionalAttrs (swapModels != { }) {
      mlx-swap-models = {
        swap = true;
        exclusive = false;
        persistent = false;
        members = builtins.attrNames swapModels;
      };
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
    ./options-catalog.nix
    ./options-filters.nix
    ./options-parsers.nix
    ./options-runtime.nix
    ./packages.nix
    ./launchd.nix
    ./night-cluster.nix
  ];

  # Pass shared bindings to sub-modules via _module.args
  _module.args.mlxShared = {
    inherit
      cfg
      vllmMlxPkg
      mlxWarmupPkg
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
