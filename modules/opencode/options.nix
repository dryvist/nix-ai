# OpenCode Module Options
{ lib, ... }:
let
  mcpClient = import ../mcp/client.nix { inherit lib; };
in
{
  options.programs.opencode = {
    enable = lib.mkEnableOption "OpenCode (sst/opencode terminal agent)";

    configDir = lib.mkOption {
      type = lib.types.str;
      default = ".config/opencode";
      description = ''
        Directory (relative to $HOME) holding `opencode.json` and `command/`.
        Also the path the agent-skills registry symlinks skills and AGENTS.md
        into, so a consumer relocates the config dir here once.
      '';
    };

    commandDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Directories whose *.md files are linked into the opencode command directory (~/.config/opencode/command/ by default).";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Attrs merged into the opencode config (~/.config/opencode/opencode.json; wins over module defaults).";
    };
  }
  // mcpClient.mkClientOptions "OpenCode";
}
