# OpenCode Module
#
# Config-only (binary installed out-of-band, like qwen-code). OpenCode never
# rewrites its global config — state lives in ~/.local/share/opencode — so
# opencode.json is a plain declarative home.file, no deep-merge activation.
#
# Skills arrive via the shared agent-skills registry
# (modules/agent-skills/harnesses.nix -> ~/.config/opencode/skills symlink).
# Commands are linked per-file from commandDirs so future sources coexist.
{
  config,
  lib,
  nix-claude-code,
  ...
}:

let
  cfg = config.programs.opencode;

  aiCommon = import ../common { inherit lib config nix-claude-code; };
  permission = aiCommon.formatters.opencode.formatPermission aiCommon.permissions;

  mkCommandLinks =
    dir:
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair ".config/opencode/command/${name}" {
        source = "${dir}/${name}";
      }
    ) (
      lib.optionalAttrs (builtins.pathExists dir) (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (
          builtins.readDir dir
        )
      )
    );
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    home.file = {
      ".config/opencode/opencode.json".text = builtins.toJSON (
        lib.recursiveUpdate {
          "$schema" = "https://opencode.ai/config.json";
          inherit permission;
        } cfg.extraSettings
      );
    }
    // lib.foldl' (acc: dir: acc // mkCommandLinks dir) { } cfg.commandDirs;
  };
}
