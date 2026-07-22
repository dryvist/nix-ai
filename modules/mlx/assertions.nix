{
  config,
  lib,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg llamaSwapConfigAttrs;
in
{
  # Fail evaluation when coupled options or generated proxy contracts drift.
  assertions = lib.optionals cfg.enable [
    {
      assertion = !cfg.enablePrefixCaching || cfg.pagedKvCache;
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
        generated != null && lib.elem role generated.aliases
      ) (lib.attrNames config.services.aiStack.models);
      message = "Every AI-stack logical role must compile into the aliases of its final llama-swap physical backend.";
    }
  ];
}
