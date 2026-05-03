#
# Aider Module — Package
#
# Default: pkgs.aider-chat-full from nixpkgs (nixpkgs hierarchy, rule #1).
# Opt-in: set programs.aider.useUvx = true for a uvx aider-chat wrapper that
# always pulls the latest upstream release (matches the `hf` CLI wrapper
# pattern in modules/ai-tools.nix:183-185).
#
{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.aider;
in
{
  config = lib.mkIf cfg.enable {
    home.packages =
      if cfg.useUvx then
        [
          (pkgs.writeShellScriptBin "aider" ''
            exec ${lib.getExe pkgs.uv} tool run --from "aider-chat" aider "$@"
          '')
        ]
      else
        lib.optional (cfg.package != null) cfg.package;
  };
}
