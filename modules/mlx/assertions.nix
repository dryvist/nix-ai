{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.mlx;
in
{
  assertions = lib.optionals cfg.enable [
    {
      assertion = lib.elem cfg.modelServerBackend cfg.enabledBackends;
      message =
        "programs.mlx.modelServerBackend (${cfg.modelServerBackend}) must be "
        + "listed in programs.mlx.enabledBackends "
        + "(${lib.concatStringsSep ", " cfg.enabledBackends}). Selecting a "
        + "backend that was never enabled builds a launchd command against a "
        + "server binary the closure does not contain, and fails at exec time "
        + "rather than at evaluation.";
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
          && profile.maxNumSeqs == (cfg.modelConcurrencyLimits.${modelId} or 1)
          && !config.programs.mlx.clusterMode.enable
        )
      ) (lib.attrNames cfg.modelMtpProfiles);
      message = "An enabled programs.mlx.modelMtpProfiles entry requires the native mlx-vlm backend, a drafter, matching worker concurrency, and non-cluster mode. MTP must not silently enter a clustered role.";
    }
    (
      let
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
          doesn't match is silently dropped — the flags never reach a worker.
          If this is an ad-hoc model, select it in the catalog.
        '';
      }
    )
  ];
}
