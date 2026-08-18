# Cursor CLI Module Options
{ lib, ... }:
let
  mcpClient = import ../mcp/client.nix { inherit lib; };
in
{
  options.programs.cursor = {
    enable = lib.mkEnableOption "Cursor CLI (cursor-agent terminal agent)";

    vimMode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable vim mode in the Cursor CLI (editor.vimMode in cli-config.json).";
    };

    approvalMode = lib.mkOption {
      type = lib.types.enum [
        "allowlist"
        "auto-review"
        "unrestricted"
      ];
      default = "allowlist";
      description = ''
        How the Cursor CLI decides to run commands not in `permissions.allow`:
        `allowlist` (prompt for anything not allowed), `auto-review`
        (route through the built-in classifier), or `unrestricted`.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Attrs merged into ~/.cursor/cli-config.json (wins over module defaults).";
    };
  }
  // mcpClient.mkClientOptions "Cursor";
}
