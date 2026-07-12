# MCP Runtime — Home-Manager Module
#
# Owns all runtime infrastructure required to make the MCP server definitions
# in `./default.nix` actually executable on a user's machine:
#
#   - doppler-mcp wrapper (Doppler secret injection for any MCP server)
#   - splunk-mcp-connect helper
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
  # this module is about Doppler/Splunk MCP runtime wrappers, not the
  # upstream Claude Desktop bridge.
  options.programs.mcpRuntime = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install MCP runtime infrastructure (doppler-mcp,
        splunk-mcp-connect). Disable to opt out entirely.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      # doppler-mcp — wraps any MCP server command with Doppler secret
      # injection. Used by mcp/default.nix `withDoppler` callers.
      # No synchronous preflight (caused 100% MCP startup failures with
      # ~17 parallel servers). See modules/mcp/README.md → Troubleshooting.
      (pkgs.writeShellApplication {
        name = "doppler-mcp";
        runtimeInputs = [ pkgs.doppler ];
        text = builtins.readFile ./scripts/doppler-mcp.sh;
      })

      # splunk-mcp-connect — Splunk MCP App stdio proxy via mcp-remote.
      # Reads SPLUNK_MCP_ENDPOINT/SPLUNK_MCP_TOKEN injected by doppler-mcp.
      (pkgs.writeShellApplication {
        name = "splunk-mcp-connect";
        runtimeInputs = [ pkgs.bun ];
        text = builtins.readFile ./scripts/splunk-mcp-connect.sh;
      })
    ];
  };
}
