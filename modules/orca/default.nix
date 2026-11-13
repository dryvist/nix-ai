# Orca desktop app (stablyai/orca), off by default.
#
# Installs the pinned release bundle and puts its `orca` CLI on PATH. Orca's
# GitHub features use the gh command's existing authentication; this module
# configures no credential.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.orca;
  package = pkgs.callPackage ./package.nix { };
in
{
  options.programs.orca.enable = lib.mkEnableOption "the Orca desktop app";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.meta.availableOn pkgs.stdenv.hostPlatform package;
        message = "programs.orca.enable is supported on aarch64-darwin only.";
      }
    ];

    home.packages = [ package ];
  };
}
