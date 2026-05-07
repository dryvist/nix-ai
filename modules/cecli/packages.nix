#
# cecli Module — Package Install
#
# Builds cecli directly from package.nix via pkgs.callPackage — same
# pattern as modules/mcp/module.nix (pal-mcp). This avoids requiring
# consumers to register an overlay (nix-ai.overlays.default), which
# causes infinite recursion in nix-darwin when useGlobalPkgs = true.
#
{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.cecli;
  cecliPkg = pkgs.callPackage ./package.nix { };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      cecliPkg
    ];
  };
}
