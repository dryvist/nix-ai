# MCP Runtime — Home-Manager Module
#
# Owns all runtime infrastructure required to make the MCP server definitions
# in `./default.nix` actually executable on a user's machine:
#
#   - OpenBao-backed splunk-mcp-connect helper
#
# This module is the load-bearing piece for the MCP sub-flake's
# self-containment guarantee: importing it (alone) gives a consumer a working
# MCP runtime, with no cross-tool runtime dependencies on Claude or Codex.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.mcpRuntime;
in
{
  imports = [ ./default.nix ];

  # Namespace note: home-manager 25.11+ ships `programs.mcp` (Claude Desktop
  # MCP integration). We use `programs.mcpRuntime` to avoid the collision —
  # this module is about secret-backed MCP runtime wrappers, not the
  # upstream Claude Desktop bridge.
  options.programs.mcpRuntime = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install MCP runtime infrastructure
        (splunk-mcp-connect). Disable to opt out entirely.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      # splunk-mcp-connect — fetches the canonical Splunk connection from
      # OpenBao using an ambient-env AppRole, then starts the Splunk MCP App
      # stdio proxy via mcp-remote.
      (pkgs.writeShellApplication {
        name = "splunk-mcp-connect";
        runtimeInputs = [
          pkgs.bun
          pkgs.curl
          pkgs.jq
        ];
        text = builtins.readFile ./scripts/splunk-mcp-connect.sh;
      })
    ];
  };
}
