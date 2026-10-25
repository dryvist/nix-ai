# Shared MCP profile regression tests
{
  pkgs,
  hmConfig,
  hmConfigMcpLaunchPrefix,
  hmConfigGatewayCallers,
}:
let
  args = {
    inherit pkgs hmConfig hmConfigMcpLaunchPrefix hmConfigGatewayCallers;
  };
in
(import ./mcp-profile.nix args)
// (import ./mcp-gateway-callers.nix args)
// (import ./mcp-gateway-route.nix args)
// (import ./mcp-launch.nix args)
// (import ./mcp-launch-contract.nix args)
