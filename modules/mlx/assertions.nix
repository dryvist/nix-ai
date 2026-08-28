{
  config,
  lib,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg llamaSwapConfigAttrs allModels;
in
{
  # Fail evaluation when coupled options or generated proxy contracts drift.
  assertions = lib.optionals cfg.enable [
    {
      assertion = cfg.modelServerBackend == "mlx-lm" && cfg.enabledBackends == [ "mlx-lm" ];
      message = "programs.mlx must use only the enabled mlx-lm backend; vllm-mlx remains preserved but disabled.";
    }
    {
      assertion = cfg.singleModel == null || builtins.hasAttr cfg.singleModel allModels;
      message = "programs.mlx.singleModel must name a physical id already compiled into the model registry (a services.aiStack role or programs.mlx.models entry).";
    }
    {
      assertion = cfg.modelServerBackend != "vllm-mlx" || !cfg.enablePrefixCaching || cfg.pagedKvCache;
      message = ''
        programs.mlx.enablePrefixCaching requires programs.mlx.pagedKvCache to
        also be true. vllm-mlx builds the prefix-sharing index inside the paged
        KV cache. Set both options true or both false.
      '';
    }
    {
      assertion = lib.all (
        modelId:
        let
          profile = cfg.modelMtpProfiles.${modelId};
          backend = cfg.modelBackends.${modelId} or cfg.modelServerBackend;
        in
        !profile.enable
        || (
          backend == "mlx-vlm-native"
          && lib.elem "mlx-vlm-native" cfg.enabledBackends
          && profile.drafterModel != null
          && profile.maxNumSeqs == (cfg.modelConcurrencyLimits.${modelId} or cfg.proxy.concurrencyLimit)
          && !config.programs.mlx.clusterMode.enable
        )
      ) (lib.attrNames cfg.modelMtpProfiles);
      message = "An enabled programs.mlx.modelMtpProfiles entry requires the native mlx-vlm backend, a drafter, matching proxy/worker concurrency, and non-cluster mode. MTP must not silently enter a clustered role.";
    }
    {
      assertion = lib.all (
        role:
        let
          physical = config.services.aiStack.models.${role};
          generated = llamaSwapConfigAttrs.models.${physical} or null;
        in
        physical != "" && generated != null && lib.elem role generated.aliases
      ) (lib.attrNames config.services.aiStack.models);
      message = "Every AI-stack logical role must resolve to a non-empty physical model and compile into that llama-swap backend's aliases.";
    }
    {
      # A request naming a model must be served by that model's weights or
      # must error. An alias is legitimate only when it is a ROLE name bound
      # to the one entry that serves it; an alias equal to some OTHER entry's
      # physical id makes llama-swap answer with the wrong weights, 200 OK and
      # the requested name echoed back. That is how one model's throughput was
      # published under two other models' names.
      assertion =
        let
          emitted = llamaSwapConfigAttrs.models;
          physicalIds = lib.attrNames allModels;
          foreignAliases = lib.concatMap (
            id: lib.filter (alias: alias != id && lib.elem alias physicalIds) (emitted.${id}.aliases or [ ])
          ) (lib.attrNames emitted);
        in
        foreignAliases == [ ];
      message = ''
        A llama-swap entry declares an alias that is another model's physical
        id. Aliases may only be role names bound to the entry that actually
        serves them — never a different model's id, which would silently
        substitute weights. A caller naming an unserved model must get a 404.
      '';
    }
    {
      assertion = !cfg.judge.enable || !(builtins.hasAttr cfg.judge.model allModels);
      message = ''
        programs.mlx.judge.model (${cfg.judge.model}) collides with a physical
        id already registered as a resident/swap model. The judge's own
        llama-swap entry would silently overwrite that entry's config.
        Pick a different physical id for the judge.
      '';
    }
    (
      let
        # A modelExtraArgs key is legitimate for either of the two consumers
        # that actually read it (modules/mlx/default.nix registryModels,
        # modules/mlx/options-catalog.nix argsViaExtraArgs): a role-registry
        # physical id, or an enabled programs.mlx.catalog entry compiled as
        # class = "resident" — those read modelExtraArgs unconditionally,
        # role or no role (a host may assign the role separately).
        catalogData = import ./catalog-data.nix;
        residentCatalogPhysicalIds = lib.mapAttrsToList (name: _: catalogData.${name}.model) (
          lib.filterAttrs (_: sel: sel.enable && sel.class == "resident") cfg.catalog
        );
        registryPhysicalIds = lib.unique (
          lib.attrValues config.services.aiStack.models ++ residentCatalogPhysicalIds
        );
        badKeys = lib.filter (key: !(lib.elem key registryPhysicalIds)) (lib.attrNames cfg.modelExtraArgs);
      in
      {
        assertion = badKeys == [ ];
        message = ''
          programs.mlx.modelExtraArgs.${lib.concatStringsSep ", " badKeys} names
          no physical model in the role registry (services.aiStack.models) or
          an enabled resident-class programs.mlx.catalog entry. A key that
          doesn't match is silently dropped — the flags never reach any
          worker, which can silently drop a required flag (e.g.
          --tool-call-parser) and cause every request to that worker to fail.
          If this is an ad-hoc (non-registry) model, set
          programs.mlx.models.<name>.extraArgs instead.
        '';
      }
    )
  ];
}
