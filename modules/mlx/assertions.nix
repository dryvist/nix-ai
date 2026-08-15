{
  config,
  lib,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg llamaSwapConfigAttrs allModels;
  # Documented host wired-memory ceiling (nix-darwin appleSiliconTunables,
  # iogpu.wired_limit_mb = 102400 on the 128 GiB Macs this module targets;
  # see modules/mlx/options-residency.nix). Not readable from this module —
  # nix-darwin owns the sysctl — so it is named here rather than re-derived.
  wiredCeilingGiB = 100;
in
{
  # Fail evaluation when coupled options or generated proxy contracts drift.
  assertions = lib.optionals cfg.enable [
    {
      # The residency invariant documented in options-residency.nix (lines
      # 9, 40) and options-runtime.nix (lines 11, 72-74) but never enforced:
      # maxResidentWorkers * memoryHardLimitGb must not exceed the host wired
      # ceiling, or the module can represent a config the hardware cannot
      # honor (host-wide swap/thrash under memory pressure).
      assertion = cfg.maxResidentWorkers * cfg.memoryHardLimitGb <= wiredCeilingGiB;
      message =
        let
          product = cfg.maxResidentWorkers * cfg.memoryHardLimitGb;
        in
        ''
          programs.mlx: maxResidentWorkers (${toString cfg.maxResidentWorkers}) *
          memoryHardLimitGb (${toString cfg.memoryHardLimitGb}) = ${toString product} GiB,
          exceeding the documented wired ceiling of ${toString wiredCeilingGiB} GiB.
          Lower memoryHardLimitGb to fit the raised worker count, or lower
          maxResidentWorkers back down.
        '';
    }
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
  ];
}
