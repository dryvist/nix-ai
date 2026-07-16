# OpenCode Module Options
{ lib, ... }:
let
  mcpClient = import ../mcp/client.nix { inherit lib; };
in
{
  options.programs.opencode = {
    enable = lib.mkEnableOption "OpenCode (sst/opencode terminal agent)";

    commandDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Directories whose *.md files are linked into ~/.config/opencode/command/.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Attrs merged into ~/.config/opencode/opencode.json (wins over module defaults).";
    };
  }
  // mcpClient.mkClientOptions "OpenCode";
}
