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

  settings = {
    "$schema" = "https://opencode.ai/config.json";
    inherit permission;
  };

  mdFiles =
    dir:
    lib.optionalAttrs (builtins.pathExists dir) (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (builtins.readDir dir)
    );

  mkCommandLinks =
    dir:
    lib.mapAttrs' (name: _: {
      name = ".config/opencode/command/${name}";
      value = {
        source = "${dir}/${name}";
      };
    }) (mdFiles dir);
in
{
  imports = [ ./options.nix ];

  # Shadow home-manager 26.05's upstream programs.opencode module — this
  # module owns the option namespace (same pattern as antigravity-cli).
  disabledModules = [ "programs/opencode.nix" ];

  config = lib.mkIf cfg.enable {
    home.file = {
      ".config/opencode/opencode.json".text = builtins.toJSON (
        lib.recursiveUpdate settings cfg.extraSettings
      );
    }
    // lib.foldl' (acc: dir: acc // mkCommandLinks dir) { } cfg.commandDirs;
  };
}
