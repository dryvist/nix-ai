{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.qwen-code;
  json = pkgs.formats.json { };
in
{
  options.programs.qwen-code.nativeHooks = lib.mkOption {
    inherit (json) type;
    default = { };
    description = "Hooks registered through a separate Qwen extension.";
  };

  config = lib.mkIf (cfg.enable && cfg.nativeHooks != { }) {
    home.file.".qwen/extensions/nix-ai-hooks/qwen-extension.json".source =
      json.generate "qwen-nix-ai-hooks.json"
        {
          name = "nix-ai-hooks";
          version = "1.0.0";
          hooks = cfg.nativeHooks;
        };
  };
}
