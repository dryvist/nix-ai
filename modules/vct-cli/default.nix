{
  config,
  lib,
  pkgs,
  vct-cribl-cli,
  vct-splunk-cli,
  ...
}:

let
  cfg = config.programs.vctCli;
  packages = import ./packages.nix {
    inherit
      pkgs
      vct-cribl-cli
      vct-splunk-cli
      ;
  };
in
{
  options.programs.vctCli.enable = lib.mkEnableOption "VisiCore Cribl and Splunk operator CLIs";

  config = lib.mkIf cfg.enable {
    home.packages = [
      packages.vct-cribl-cli
      packages.vct-splunk-cli
    ];
  };
}
