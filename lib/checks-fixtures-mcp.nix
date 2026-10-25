# MCP regression fixtures
{ mkHmConfig }:
{
  # Render gateway routes in every MCP-capable harness with no topology value.
  # The empty base keeps the fixture host-free; checks inspect only route headers.
  hmConfigGatewayCallers = mkHmConfig [
    (
      { lib, ... }:
      {
        programs.aiMcp = {
          gatewayBaseUrl = "";
          onDemandServers = lib.mkForce [ ];
        };
      }
    )
  ];

  # A per-server launchPrefix plus a launchPrefixFor hook
  # (lib/checks/mcp.nix mcp-launch-prefix).
  hmConfigMcpLaunchPrefix = mkHmConfig [
    (
      { lib, ... }:
      {
        programs.aiMcp = {
          launchPrefixFor = vars: [ "/test/injector" ] ++ vars ++ [ "--" ];
          servers = {
            zammad.launchPrefix = [
              "/test/wrapper"
              "--flag"
              "--"
            ];
            vikunja.disabled = lib.mkForce false;
          };
          # A consumer appending one name, exactly as a host does, must keep
          # the curated list (lib/checks/mcp.nix mcp-on-demand-merge).
          onDemandServers = lib.mkAfter [ "vikunja" ];
          extraOnDemandMcpServers.http-test = {
            type = "http";
            url = "https://example.invalid/mcp";
            bearer_token_env_var = "TEST_TOKEN";
          };
        };
        programs.codex.onDemandMcpServers = [ "http-test" ];
      }
    )
  ];

}
