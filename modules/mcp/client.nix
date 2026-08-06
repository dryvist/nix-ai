# Shared MCP client helpers
#
# Every AI client module renders the same shared catalog into its own config
# format: filter out the per-tool excludes, then run a tool-specific
# normalizer. This centralizes that filter/render step and the two duplicated
# option definitions (excludedMcpServers + mcpServerNames) so each client only
# supplies its normalizer.
{ lib }:
{
  # programs.aiMcp.enabledServers is already filtered for disabled/global-exclude
  # (modules/mcp/default.nix) — only the per-tool exclude list applies here.
  #
  # `client` is this renderer's own name, used to resolve a server's
  # clientNameEnv. The key itself needs no stripping: every normalizer is a key
  # allowlist and none of them list it.
  renderServers =
    {
      enabledServers,
      excluded ? [ ],
      normalize,
      client ? null,
    }:
    let
      withClientName =
        server:
        if client == null || server.clientNameEnv == null then
          server
        else
          server
          // {
            env = server.env // {
              ${server.clientNameEnv} = client;
            };
          };
    in
    lib.mapAttrs (_: server: normalize (withClientName server)) (
      lib.filterAttrs (name: _: !lib.elem name excluded) enabledServers
    );

  mkClientOptions = tool: {
    excludedMcpServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional MCP servers to exclude from the shared cross-agent profile for ${tool} only.";
    };

    mcpServerNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      description = "Names of MCP servers emitted to ${tool}'s config; read-only.";
    };
  };
}
