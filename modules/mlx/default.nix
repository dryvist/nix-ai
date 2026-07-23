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

  # Preserved backend implementation. It remains unavailable to workers unless
  # explicitly included in enabledBackends after future requalification.
  vllmMlxVersion = versions.vllmMlx;
  parakeetMlxVersion = versions.parakeetMlx;
  mlxVlmVersion = versions.mlxVlm;

  # Official Apple mlx_lm.server wrapper.
  # The LaunchAgent needs a Nix store path (not a PATH lookup), so the
  # derivation lives here. Also added to home.packages for CLI access.
  #
  # MLX-driven version set: core MLX is the primary driver of every version
  # below (python, mlx, mlx-lm, transformers). One set, updated together and
  # deliberately from MLX's official install matrix.
  # Python rule: MLX supports Python 3.10 or newer with no stated upper bound.
  # Following the stay-latest-within-MLX principle, pick the newest CPython minor
  # for which the pinned mlx version publishes a wheel. mlx ${versions.mlx} ships
  # cp310 through cp314, so the pin is 3.14 (cp314 GPU import validated
  # 2026-07-19). Bump mechanically when mlx adds a newer cp wheel tag.
  # mlx and mlx-lm are a lockstep pair; transformers is pinned for mlx-lm import
  # compatibility (history in lib/versions.nix).
  # These pins are renovate-excluded on purpose: an unpinned bump can split the
  # set and desync the two cluster nodes. The exclusions live in the renovate
  # config, landed separately by the ceiling-fix work; do not float any member.
  mlxPin = "mlx==${versions.mlx}";
  mlxLmPin = "mlx-lm==${versions.mlxLm}";
  transformersPin = "transformers==${versions.transformers}";

  # Single source for the CPython minor every uvx invocation in this module
  # resolves. Why it exists: the cluster rank runs uvx on BOTH the coordinator
  # and the worker; with no `--python`, uv resolved a different CPython build per
  # node, so the two ranks loaded mismatched mlx ABIs and failed to rendezvous.
  # Pin every module uvx call to this one version so both nodes match. Sourced
  # from lib/python.nix so there is exactly one declaration (no per-host, no
  # per-invocation value). Value and bump rule: see the MLX-driven set above.
  uvPythonVersion = (import ../../lib/python.nix { inherit pkgs; }).pythonVersion;

  vllmMlxPatchedWheel = import ./vllm-mlx-patch.nix { inherit pkgs vllmMlxVersion; };
  vllmMlxPkg = pkgs.writeShellScriptBin "vllm-mlx" ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "${vllmMlxPatchedWheel}/vllm_mlx-${vllmMlxVersion}-py3-none-any.whl" --with "${mlxPin}" --with "${mlxLmPin}" --with "${transformersPin}" vllm-mlx "$@"
  '';
  vllmMlxServerAdapterPkg = pkgs.writeShellScriptBin "mlx-model-server" ''
    if [[ "$1" != "--model" || -z "''${2:-}" ]]; then
      echo "usage: mlx-model-server --model MODEL [server options]" >&2
      exit 2
    fi
    model="$2"
    shift 2
    exec ${lib.getExe vllmMlxPkg} serve "$model" "$@"
  '';

  mlxLmServerPkg = pkgs.writeShellScriptBin "mlx-lm-server" ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "${mlxLmPin}" --with "${mlxPin}" --with "${transformersPin}" mlx_lm.server "$@"
  '';
  mlxModelServerPkg =
    {
      mlx-lm = mlxLmServerPkg;
      vllm-mlx = vllmMlxServerAdapterPkg;
    }
    .${cfg.modelServerBackend};
  mlxWarmupPkg = pkgs.writeShellScriptBin "mlx-warmup" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/mlx-warmup.py} "$@"
  '';
  # mlx-watchdog — periodic serving probe that kickstarts the proxy when it is up
  # but not serving (KeepAlive only catches process exit). Probes a real
  # completion: every observed failure mode still answers /v1/models with 200.
  # writeShellApplication shellcheck-validates the script at eval time.
  mlxWatchdogPkg = pkgs.writeShellApplication {
    name = "mlx-watchdog";
    runtimeInputs = with pkgs; [
      curl
      coreutils
      gawk
      jq
    ];
    text = builtins.readFile ./scripts/mlx-watchdog.sh;
  };

  # llama-swap sits on the stable API port and supervises official mlx_lm workers.
  # Sourced from nixpkgs-unstable: 25.11-darwin froze it at v165 on 2025-09-22
  # with no backports while unstable kept moving (currently v211). See nix-ai#801.
  llamaSwapPkg = nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.llama-swap;

  # Proxy launcher — reaps orphaned mlx_lm.server workers, then execs llama-swap.
  # A worker outliving its proxy keeps its engine port bound, which makes every
  # subsequent start fail on bind and 429 forever; reaping on the way up is what
  # keeps a restart an actual remedy. Rationale in llama-swap-launch.sh.
  llamaSwapLaunchPkg = pkgs.writeShellApplication {
    name = "llama-swap-launch";
    # No procps: pgrep/pkill are called by absolute path (see the script) —
    # Darwin's procps ships only ps/sysctl/top/watch.
    runtimeInputs = [
      llamaSwapPkg
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/llama-swap-launch.sh;
  };

  apiUrl = "http://${cfg.host}:${toString cfg.port}/v1";
  launchAgentLabel = "dev.mlx-model-server";
  warmupAgentLabel = "dev.mlx-model-server.warmup";
  modelServerProcessPattern =
    {
      mlx-lm = "/mlx_lm\\.server";
      vllm-mlx = "vllm-mlx serve";
    }
    .${cfg.modelServerBackend};

  # Shared per-backend env — split to worker-env.nix (12KB file-size gate).
  inherit (import ./worker-env.nix { inherit lib cfg; }) workerEnv;

  # Mutable runtime config path — llama-swap reads this with --watch-config.
  # mlx-discover merges auto-discovered models into this file at runtime.
  # The Nix-generated llamaSwapConfigFile seeds this on first activation.
  llamaSwapRuntimeConfigPath = "${config.home.homeDirectory}/.config/mlx/llama-swap.json";

  # MLX model-server command builder — split for the 12KB file-size gate.
  inherit
    (import ./model-server-cmd.nix {
      inherit
        lib
        cfg
        mlxModelServerPkg
        ;
    })
    mkModelCmd
    ;

  # Role registry (services.aiStack.models): role-name -> physical model ID.
  # Single source of truth.
  roleModels = config.services.aiStack.models;

  # Group roles by physical model. One backend serves many role aliases.
  rolesByPhysical = lib.groupBy (role: roleModels.${role}) (lib.attrNames roleModels);

  # One entry per unique physical model. Every model — including the entry
  # owning the "default" alias — inherits the uniform proxy idle TTL.
  # Preloading is done by the warmup LaunchAgent (mlx-warmup.py reading
  # MLX_PRELOAD_MODELS_JSON), NOT llama-swap's hooks.on_startup.preload:
  # that hook's request shape is not portable across MLX backends, so llama-swap
  # would start the worker, fail the preload, and stop it — residents cold.
  # After proxy.idleTtl of idle a model unloads and the next request reloads
  # it (~15-30 s).
  #
  # useModelName makes llama-swap rewrite the OpenAI-compatible request body's
  # `model` field to the physical model id before forwarding to the MLX server.
  # MLX servers validate the model field against the loaded model name and
  # return 404 for unknown names — without this rewrite, callers
  # using a capability-class alias (e.g. `model: "default"`) hit
  #   "The model `default` does not exist."
  # even though llama-swap routed the request correctly. With it, the alias
  # works end-to-end through the local proxy.
  # Default llama-swap filters applied to every model in the registry.
  # See modules/mlx/options-filters.nix for the schema and reasoning.
  # Filters run at the proxy layer BEFORE the request hits the MLX server, so they
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
        mkModelCmd physical + lib.optionalString (extraArgs != [ ]) (" " + lib.escapeShellArgs extraArgs);
      ttl = cfg.modelTtls.${physical} or cfg.proxy.idleTtl;
      env = workerEnv;
      checkEndpoint = "/v1/models";
      aliases = roles;
      useModelName = physical;
      concurrencyLimit = cfg.modelConcurrencyLimits.${physical} or cfg.proxy.concurrencyLimit;
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
        mkModelCmd name
        + lib.optionalString (modelCfg.extraArgs != [ ]) (
          " " + lib.concatStringsSep " " modelCfg.extraArgs
        );
      ttl = if modelCfg.ttl > 0 then modelCfg.ttl else cfg.proxy.idleTtl;
      env = workerEnv;
      checkEndpoint = "/v1/models";
      concurrencyLimit = cfg.modelConcurrencyLimits.${name} or cfg.proxy.concurrencyLimit;
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
    # logLevel="info" keeps lifecycle/routing evidence without prompt bodies.
    # logToStdout="both" merges proxy and MLX server output into one stream.
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
  };

  # Use pkgs.writeText because command strings embed Nix store paths.
  llamaSwapConfigFile = pkgs.writeText "llama-swap-config.json" (
    builtins.toJSON llamaSwapConfigAttrs
  );
in
{
  imports = [
    ./options-renamed.nix
    ./options-proxy.nix
    ./options-server.nix
    ./options-cache.nix
    ./options-batching.nix
    ./options-catalog.nix
    ./options-filters.nix
    ./options-parsers.nix
    ./options-runtime.nix
    ./options-cluster.nix
    ./assertions.nix
    ./packages.nix
    ./launchd.nix
    ./launchd-watchdog.nix
    ./cluster-mode.nix
    ./cluster-mode-maintenance.nix
  ];

  # Pass shared bindings to sub-modules via _module.args
  _module.args.mlxShared = {
    inherit
      cfg
      mlxModelServerPkg
      vllmMlxPkg
      mlxWarmupPkg
      mlxWatchdogPkg
      vllmMlxVersion
      parakeetMlxVersion
      mlxVlmVersion
      apiUrl
      uvPythonVersion
      launchAgentLabel
      warmupAgentLabel
      modelServerProcessPattern
      llamaSwapPkg
      llamaSwapLaunchPkg
      llamaSwapConfigFile
      llamaSwapConfigAttrs
      llamaSwapRuntimeConfigPath
      ;
  };

}
