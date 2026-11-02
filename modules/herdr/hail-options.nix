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

    summarizer = {
      enable = lib.mkEnableOption "local summaries for blocked herdr agents";

      baseUrl = lib.mkOption {
        type = lib.types.addCheck lib.types.str (
          value:
          let
            scheme =
              if lib.hasPrefix "http://" value then
                "http://"
              else if lib.hasPrefix "https://" value then
                "https://"
              else
                "";
            rest = lib.removePrefix scheme value;
            authority = builtins.head (lib.splitString "/" rest);
            isLoopbackHost =
              host:
              authority == host
              || (
                lib.hasPrefix "${host}:" authority
                && (
                  let
                    port = lib.removePrefix "${host}:" authority;
                  in
                  port != "" && builtins.match "[0-9]+" port != null
                )
              );
          in
          scheme != ""
          && !lib.hasInfix "?" value
          && !lib.hasInfix "#" value
          && !lib.hasInfix "@" authority
          && lib.any isLoopbackHost [
            "localhost"
            "127.0.0.1"
            "[::1]"
          ]
        );
        default = "http://127.0.0.1:11434/v1";
        description = "Loopback OpenAI-compatible endpoint used for blocked-agent summaries.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "fast";
        description = "Local model name sent to the OpenAI-compatible chat completions endpoint.";
      };

      timeoutMs = lib.mkOption {
        type = lib.types.ints.between 1 30000;
        default = 1500;
        description = "Maximum time to wait for a local summary before posting without one.";
      };

      maxInputChars = lib.mkOption {
        type = lib.types.ints.between 1 12000;
        default = 4000;
        description = "Maximum recent cleaned pane characters sent to the local summarizer.";
      };
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
