# MCP Runtime — Home-Manager Module
#
# Owns any local runtime infrastructure a MCP server definition in
# `./default.nix` needs to actually run (wrapper binaries, launch scripts).
# Currently empty: every server that used to need one (splunk) now dials the
# shared agentgateway MCP layer instead of launching a local process — see
# `./catalog.nix`'s `gatewayRoute` entries.
#
# This module is the load-bearing piece for the MCP sub-flake's
# self-containment guarantee: importing it (alone) gives a consumer a working
# MCP runtime, with no cross-tool runtime dependencies on Claude or Codex.
{
  config,
  lib,
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
        Whether to install local MCP runtime infrastructure. Currently a
        no-op placeholder — nothing under the catalog needs a local wrapper
        today. Disable to opt out of any future one wholesale.
      '';
    };
  };

  config = lib.mkIf cfg.enable { };
}
