# Shared MCP client helpers
#
# Every AI client module renders the same shared catalog into its own config
# format: filter out the per-tool excludes, then run a tool-specific
# normalizer. This centralizes that filter/render step and the two duplicated
# option definitions (excludedMcpServers + mcpServerNames) so each client only
# supplies its normalizer.
{ lib }:
let
  callerKeyEnv = id: "GATEWAY_KEY_" + lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] id);
  keyEnvFor = id: override: if override == null then callerKeyEnv id else override;
in
{
  inherit callerKeyEnv keyEnvFor;

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
      callerId ? null,
      callerKeyEnvOverride ? null,
      callerIds ? [ ],
    }:
    let
      callerKeyEnv = keyEnvFor callerId callerKeyEnvOverride;
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
      withCallerKey =
        server:
        if server.gatewayRoute && callerId != null then
          server // { gatewayKeyEnv = callerKeyEnv; }
        else
          server;
      eligible = lib.filterAttrs (
        name: server: !(lib.elem name excluded) && (!server.gatewayRoute || callerId != null)
      ) enabledServers;
    in
    assert
      callerId == null
      || lib.elem callerId callerIds
      || throw "MCP callerId `${callerId}` is not registered in homelab-contracts callers.json";
    assert
      callerId != null || callerKeyEnvOverride == null || throw "MCP callerKeyEnv requires a callerId";
    assert
      callerKeyEnvOverride == null
      || builtins.match "[A-Z_][A-Z0-9_]*" callerKeyEnvOverride != null
      || throw "MCP callerKeyEnv must be an environment-variable name";
    lib.mapAttrs (_: server: normalize (withClientName (withCallerKey server))) eligible;

  mkClientOptions = tool: {
    callerId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Caller ID from homelab-contracts for authenticated agentgateway MCP routes.";
    };

    callerKeyEnv = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Optional override for the environment variable that holds this harness's gateway key.";
    };

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

    renderedMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      readOnly = true;
      internal = true;
      description = "Normalized MCP configuration emitted by ${tool}; read-only for regression checks.";
    };
  };
}
