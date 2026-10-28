# herdr-hail excerpt size: both renderers must hand hail contextLines = 40.
#
# Each module restates upstream's defaults and renders them as config.json.
# This reads the settings each module renders and forces them, so reverting
# either literal to upstream's 12 fails evaluation.
{ pkgs, hmConfigDarwin }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  expected = 40;

  darwin = hmConfigDarwin.config.services.herdr.hail.renderedSettings;

  nixos =
    (lib.evalModules {
      specialArgs = {
        inherit pkgs;
        herdr-hail-src = null;
      };
      modules = [
        ../../modules/herdr/hail.nix
        {
          # Stand-ins for the NixOS options the unit also writes to. Only
          # renderedSettings is read here, so these are never forced.
          options = {
            assertions = lib.mkOption {
              type = lib.types.listOf lib.types.raw;
              default = [ ];
            };
            environment = lib.mkOption {
              type = lib.types.raw;
              default = { };
            };
            systemd = lib.mkOption {
              type = lib.types.raw;
              default = { };
            };
            services.herdr = {
              enable = lib.mkOption { type = lib.types.bool; };
              user = lib.mkOption { type = lib.types.str; };
              stateDir = lib.mkOption { type = lib.types.str; };
              socketPath = lib.mkOption { type = lib.types.str; };
              onFailureUnit = lib.mkOption { type = lib.types.nullOr lib.types.str; };
            };
          };
          config.services.herdr = {
            enable = true;
            user = "herdr";
            stateDir = "/var/lib/herdr";
            socketPath = "/run/herdr/herdr.sock";
            onFailureUnit = null;
            hail.enable = true;
          };
        }
      ];
    }).config.services.herdr.hail.renderedSettings;
in
{
  herdr-hail-context-regression =
    assert builtins.deepSeq darwin (builtins.deepSeq nixos true);
    assert lib.assertMsg (darwin.contextLines == expected)
      "herdr-hail LaunchAgent renders contextLines ${toString darwin.contextLines}, expected ${toString expected}";
    assert lib.assertMsg (nixos.contextLines == expected)
      "herdr-hail NixOS unit renders contextLines ${toString nixos.contextLines}, expected ${toString expected}";
    helpers.mkMarker "check-herdr-hail-context-regression" "herdr-hail renders contextLines ${toString expected} in both modules.";
}
