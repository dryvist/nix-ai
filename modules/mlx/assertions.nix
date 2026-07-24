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
        role:
        let
          physical = config.services.aiStack.models.${role};
          generated = llamaSwapConfigAttrs.models.${physical} or null;
        in
        physical != "" && generated != null && lib.elem role generated.aliases
      ) (lib.attrNames config.services.aiStack.models);
      message = "Every AI-stack logical role must resolve to a non-empty physical model and compile into that llama-swap backend's aliases.";
    }
  ];
}
