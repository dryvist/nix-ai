# MCP launch prefix and on-demand regression tests
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
  # zammad's own launchPrefix wins over launchPrefixFor; vikunja (stdio,
  # env_vars) takes the hook; time (no env_vars) and http-test (not stdio)
  # launch unchanged.
  launchCfg = hmConfigMcpLaunchPrefix.config.programs.aiMcp;
  launched = launchCfg.onDemandEnabledServers // launchCfg.enabledServers;
  codexOnDemandNames = hmConfigMcpLaunchPrefix.config.programs.codex.mcpServerNames;
  claudeHttpTest =
    builtins.fromJSON
      hmConfigMcpLaunchPrefix.config.home.file.".claude/mcp-available/http-test.json".text;
  catalogZammad = launchCfg.servers.zammad;
  catalogVikunja = launchCfg.servers.vikunja;
in
{
  mcp-launch-prefix =
    assert
      launched.zammad.command == "/test/wrapper"
      &&
        launched.zammad.args == [
          "--flag"
          "--"
          catalogZammad.command
        ]
        ++ catalogZammad.args
      || throw "launchPrefix did not wrap zammad: ${builtins.toJSON launched.zammad}";
    assert
      launched.time.command == cfg.servers.time.command
      || throw "a server with no launchPrefix was wrapped: ${builtins.toJSON launched.time}";
    assert
      launched.vikunja.command == "/test/injector"
      && launched.vikunja.args == catalogVikunja.env_vars ++ [ "--" ] ++ [ catalogVikunja.command ]
      || throw "launchPrefixFor did not wrap vikunja: ${builtins.toJSON launched.vikunja}";
    assert
      launched.http-test.command == null
      || throw "launchPrefixFor wrapped a non-stdio server: ${builtins.toJSON launched.http-test}";
    helpers.mkMarker "check-mcp-launch-prefix" "launchPrefix wins, launchPrefixFor wraps stdio servers with env_vars, others launch directly";

  mcp-on-demand-codex-auth =
    assert
      builtins.elem "http-test" codexOnDemandNames
      || throw "Codex did not render its selected on-demand MCP server: ${builtins.toJSON codexOnDemandNames}";
    assert
      claudeHttpTest.mcpServers.http-test.headersHelper
      == "printf '{\"Authorization\":\"Bearer %s\"}\\n' \"\${TEST_TOKEN}\""
      || throw "Claude did not render the on-demand bearer env var as a per-connection header helper: ${builtins.toJSON claudeHttpTest}";
    helpers.mkMarker "check-mcp-on-demand-codex-auth" "Claude and Codex render selected on-demand bearer-authenticated MCP servers";

  mcp-on-demand-merge =
    let
      lost = builtins.filter (name: !(builtins.elem name launchCfg.onDemandServers)) (
        cfg.onDemandServers ++ [ "vikunja" ]
      );
    in
    assert
      lost == [ ]
      || throw "A consumer onDemandServers definition replaced the curated list; lost ${builtins.toJSON lost}";
    assert
      builtins.elem "http-test" hmConfigMcpLaunchPrefix.config.programs.claude.settings.enabledMcpjsonServers
      || throw "An extraOnDemandMcpServers entry is not approved in enabledMcpjsonServers";
    helpers.mkMarker "check-mcp-on-demand-merge" "A consumer's onDemandServers entries merge with the curated list";

}
