# MCP gateway route regression tests
{
  pkgs,
  hmConfig,
  hmConfigMcpLaunchPrefix,
  hmConfigGatewayCallers,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.aiMcp;
in
{
  splunk-mcp-gateway-route =
    assert
      cfg.servers.splunk.type == "http" && cfg.servers.splunk.bearer_token_env_var == "SPLUNK_MCP_TOKEN"
      || throw "Splunk MCP must be an http gateway route authenticated by SPLUNK_MCP_TOKEN: ${builtins.toJSON cfg.servers.splunk}";
    helpers.mkMarker "check-splunk-mcp-gateway-route" "Splunk MCP is a gateway route, not a local stdio launcher";

}
