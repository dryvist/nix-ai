{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.copilot-cli;
  json = pkgs.formats.json { };
  isHookMap =
    value: builtins.isAttrs value && builtins.all builtins.isList (builtins.attrValues value);
in
{
  options.programs.copilot-cli = {
    enable = lib.mkEnableOption "GitHub Copilot CLI configuration";
    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = ''
        User-level ~/.copilot/settings.json preferences. Values are written
        to the Nix store; do not put secrets here.
      '';
    };
    nativeHooks = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "Native Copilot hook event lists written to hooks/nix-ai.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optional (cfg.nativeHooks != { }) {
      assertion = isHookMap cfg.nativeHooks;
      message = "programs.copilot-cli.nativeHooks must map event names to lists.";
    };

    home.file =
      lib.optionalAttrs (cfg.settings != { }) {
        ".copilot/settings.json".source = json.generate "copilot-settings.json" cfg.settings;
      }
      // lib.optionalAttrs (cfg.nativeHooks != { }) {
        ".copilot/hooks/nix-ai.json".source = json.generate "copilot-native-hooks.json" {
          version = 1;
          hooks = cfg.nativeHooks;
        };
      };
  };
}
