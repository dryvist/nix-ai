# Shared MCP client helpers
#
# Every AI client module renders the same shared catalog into its own config
# format: filter out the per-tool excludes, then run a tool-specific
# normalizer. This centralizes that filter/render step and the two duplicated
# option definitions (excludedMcpServers + mcpServerNames) so each client only
# supplies its normalizer.
{ lib }:
{
  bridgeEnvHeaders =
    pkgs: server:
    if server.url == null || server.env_http_headers == { } then
      server
    else
      server
      // {
        command = lib.getExe (import ./mcp-remote.nix { inherit pkgs; });
        args = [
          server.url
        ]
        ++ lib.concatLists (
          lib.mapAttrsToList (name: value: [
            "--header"
            "${name}:${value}"
          ]) (builtins.removeAttrs server.headers (builtins.attrNames server.env_http_headers))
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (name: var: [
            "--header"
            "${name}:\${${var}}"
          ]) server.env_http_headers
        );
        url = null;
      };

  # programs.aiMcp.enabledServers is already filtered for disabled/global-exclude
  # (modules/mcp/default.nix). Unselected clients apply the per-tool excludes;
  # a selected facade client instead receives only the canonical route, while
  # its on-demand invocation is empty.
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
      facadeCanary ? false,
      facadeCanaryClients ? { },
      facadeServer ? null,
      onDemand ? false,
    }:
    let
      selected = facadeCanary || (client != null && (facadeCanaryClients.${client} or false));
      clientServers =
        if selected then
          if onDemand then { } else { agent-facade = facadeServer; }
        else
          lib.filterAttrs (name: _: !lib.elem name excluded) enabledServers;
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
    lib.mapAttrs (_: server: normalize (withClientName server)) clientServers;

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
