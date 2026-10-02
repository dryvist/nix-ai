# programs.mlx.roleMap — the LLM role map (lib/role-map.nix): which catalog
# model serves each router role, each model's concurrency, and the models each
# host class keeps. Defaults to the `homelab-contracts` input's copy; a
# consumer reads it (config.programs.mlx.roleMap) instead of restating any of it.
{
  config,
  lib,
  homelab-contracts,
  ...
}:
let
  cfg = config.programs.mlx;
in
{
  options.programs.mlx.roleMap = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = import ../../lib/role-map.nix { src = homelab-contracts; };
    defaultText = lib.literalExpression "homelab-contracts ansible/roles/llm_roles/files/model-roles.json";
    description = "LLM role map: `models` keyed by catalog entry, `roles` bound to a model key, `hosts` resident/swap sets per host class.";
  };

  config.assertions = lib.optionals cfg.enable (
    map
      (message: {
        assertion = false;
        message = "programs.mlx.roleMap: ${message}";
      })
      (
        import ./role-map-errors.nix {
          catalog = import ./catalog-data.nix;
          inherit (cfg) roleMap;
        }
      )
  );
}
