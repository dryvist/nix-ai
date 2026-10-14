# Shared herdr-hail options for the home-manager and NixOS service modules.
#
{
  lib,
  pkgs,
  herdr-hail-src,
  ...
}:
{
  options.services.herdr.hail = {
    enable = lib.mkEnableOption "the herdr-hail Slack/Discord bridge alongside the server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../herdr-hail/package.nix { src = herdr-hail-src; };
      defaultText = lib.literalExpression "pkgs.callPackage ../herdr-hail/package.nix { src = herdr-hail-src; }";
      description = "herdr-hail package to run.";
    };

    launchPrefix = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Arguments prepended to the herdr-hail executable in its LaunchAgent.
        Use a runtime launcher to supply tokens through the child process
        environment; do not put token values in settings.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = lib.literalExpression ''
        {
          slack = {
            enabled = true;
            channel = "C0123456789";
            allowedUsers = [ "U0123456789" ];
          };
        }
      '';
      description = ''
        Non-secret half of hail's config.json, rendered into the Nix store and
        merged over upstream's defaults, so only differing fields need
        naming. Tokens do NOT belong here — this is world-readable.
      '';
    };
  };
}
