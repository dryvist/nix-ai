# Codex MCP launch contract regression test
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
  codexLaunchContracts = {
    time = { };
    huggingface = { };
    fabric = { };
    apple-events = { };
    vikunja = {
      env_vars = [
        "VIKUNJA_API_TOKEN"
        "VIKUNJA_URL"
      ];
    };
    zammad = {
      env_vars = [
        "ZAMMAD_HTTP_TOKEN"
        "ZAMMAD_URL"
      ];
    };
  };
  codexLaunchContractMismatches = builtins.filter (
    name:
    let
      expected = codexLaunchContracts.${name};
      actual = cfg.servers.${name};
    in
    actual.startup_timeout_sec != 300
    || actual.tool_timeout_sec != 300
    || (expected ? env_vars && actual.env_vars != expected.env_vars)
  ) (builtins.attrNames codexLaunchContracts);
in
{
  codex-mcp-launch-contract =
    assert
      codexLaunchContractMismatches == [ ]
      || throw "Codex MCP launch contract mismatch: ${builtins.toJSON codexLaunchContractMismatches}";
    helpers.mkMarker "check-codex-mcp-launch-contract" "Codex MCP servers have scoped environment forwarding and 300-second startup/tool timeouts";
}
