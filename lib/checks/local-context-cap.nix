{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  maxContextWindowTokens = 200000;
  mlx = hmConfigCatalog.config.programs.mlx;
  oversized = {
    modelContextWindows = pkgs.lib.filterAttrs (
      _: tokens: tokens > maxContextWindowTokens
    ) mlx.modelContextWindows;
    modelRequestCaps = pkgs.lib.filterAttrs (
      _: flags:
      let
        tokens = flags.maxRequestTokens or null;
      in
      tokens != null && tokens > maxContextWindowTokens
    ) mlx.modelFlagOverrides;
    staticResidentContracts = pkgs.lib.filterAttrs (
      _: contract: contract.contextWindowTokens > maxContextWindowTokens
    ) mlx.staticResidentContracts;
  };
  noOversized = builtins.all (entries: entries == { }) (builtins.attrValues oversized);
in
{
  local-context-cap =
    assert
      noOversized
      || throw "local MLX generated context settings exceed 200000 tokens: ${builtins.toJSON oversized}";
    helpers.mkMarker "check-local-context-cap" "local MLX generated context settings do not exceed 200000 tokens";
}
