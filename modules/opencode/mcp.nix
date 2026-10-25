{
  pkgs,
  lib,
  config,
  cfg,
  mcpClient,
}:
let
  # Local servers carry argv and environment; remote servers carry URL/headers.
  normalizeMcpServer =
    server:
    if server.url != null then
      {
        type = "remote";
        inherit (server) url;
      }
      // lib.optionalAttrs (server.headers != { } || server.gatewayKeyEnv != null) {
        headers = server.headers // lib.optionalAttrs (server.gatewayKeyEnv != null) {
          "X-Agent-Key" = "{env:${server.gatewayKeyEnv}}";
        };
      }
    else
      {
        type = "local";
        command = [ server.command ] ++ server.args;
      }
      // lib.optionalAttrs (server.env != { }) { environment = server.env; };

  renderMcpServers =
    callerId: callerKeyEnvOverride:
    mcpClient.renderServers {
      inherit (config.programs.aiMcp) enabledServers;
      excluded = cfg.excludedMcpServers;
      normalize = normalizeMcpServer;
      client = "opencode";
      inherit callerId callerKeyEnvOverride;
      callerIds = config.programs.aiMcp.callerIds;
    };
  trustedMcpServers = renderMcpServers cfg.callerId cfg.callerKeyEnv;
  untrustedMcpServers = renderMcpServers cfg.untrustedCallerId cfg.untrustedCallerKeyEnv;
  trustedMcpConfig = pkgs.writeText "opencode-trusted-mcp.json" (
    builtins.toJSON { mcp = trustedMcpServers; }
  );
  untrustedMcpConfig = pkgs.writeText "opencode-untrusted-mcp.json" (
    builtins.toJSON { mcp = untrustedMcpServers; }
  );
in
{
  inherit trustedMcpServers untrustedMcpServers trustedMcpConfig untrustedMcpConfig;
}
