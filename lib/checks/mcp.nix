# Shared MCP profile regression tests
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
  gatewayCfg = hmConfigGatewayCallers.config;
  gatewayPolicy = gatewayCfg.programs.aiMcp;
  callerRenderer = import ../../modules/mcp/client.nix { inherit lib; };
  gatewayNames = builtins.attrNames (
    lib.filterAttrs (_: server: server.gatewayRoute) gatewayPolicy.enabledServers
  );
  gatewayOnly = servers: lib.filterAttrs (name: _: builtins.elem name gatewayNames) servers;
  callerBindings = [
    {
      label = "claude-code";
      id = gatewayCfg.programs.claude.callerId;
      override = gatewayCfg.programs.claude.callerKeyEnv;
      servers = gatewayCfg.programs.claude.renderedMcpServers;
      helper = false;
    }
    {
      label = "claude-zai";
      id = gatewayCfg.programs.claude.zaiCallerId;
      override = gatewayCfg.programs.claude.zaiCallerKeyEnv;
      servers = gatewayCfg.programs.claude.zaiRenderedMcpServers;
      helper = true;
    }
    {
      label = "codex";
      id = gatewayCfg.programs.codex.callerId;
      override = gatewayCfg.programs.codex.callerKeyEnv;
      servers = gatewayCfg.programs.codex.renderedMcpServers;
      helper = false;
    }
    {
      label = "opencode-trusted";
      id = gatewayCfg.programs.opencode.callerId;
      override = gatewayCfg.programs.opencode.callerKeyEnv;
      servers = gatewayCfg.programs.opencode.renderedMcpServers;
      helper = false;
    }
    {
      label = "opencode-untrusted";
      id = gatewayCfg.programs.opencode.untrustedCallerId;
      override = gatewayCfg.programs.opencode.untrustedCallerKeyEnv;
      servers = gatewayCfg.programs.opencode.untrustedMcpServers;
      helper = false;
    }
    {
      label = "antigravity-cli";
      id = gatewayCfg.programs.antigravity-cli.callerId;
      override = gatewayCfg.programs.antigravity-cli.callerKeyEnv;
      servers = gatewayCfg.programs.antigravity-cli.renderedMcpServers;
      helper = false;
    }
  ];
  callerEnvNames = map (binding: callerRenderer.keyEnvFor binding.id binding.override) callerBindings;
  expectedCallerEnvs = map (binding: callerRenderer.callerKeyEnv binding.id) callerBindings;
  callerEnvCollisions = lib.unique callerEnvNames != callerEnvNames;
  badCallerHeaders = lib.concatMap (
    binding:
    let
      env = callerRenderer.keyEnvFor binding.id binding.override;
      actual = gatewayOnly binding.servers;
      references =
        name: lib.filter (keyEnv: lib.hasInfix keyEnv (builtins.toJSON actual.${name})) callerEnvNames;
      headerIsOwn =
        name:
        let
          server = actual.${name};
          helper = server.headersHelper or "";
          direct = (server.env_http_headers or { })."X-Agent-Key" or null;
          web = (server.headers or { })."X-Agent-Key" or null;
          expected =
            if binding.label == "codex" then
              env
            else if lib.hasPrefix "opencode-" binding.label then
              "{env:${env}}"
            else
              "\${" + env + "}";
        in
        if binding.helper then
          lib.hasInfix "X-Agent-Key" helper && lib.hasInfix env helper
        else if binding.label == "codex" then
          direct == expected
        else
          web == expected;
    in
    lib.filter (name: references name != [ env ] || !(headerIsOwn name)) (builtins.attrNames actual)
    ++ lib.optional (builtins.attrNames actual != gatewayNames) "<route-set>"
  ) callerBindings;
  noCallerRenderers = [
    gatewayCfg.programs.antigravity-ide.renderedMcpServers
    gatewayCfg.programs.qwen-code.renderedMcpServers
  ];
  noCallerGatewayRoutes = lib.concatMap (
    servers: builtins.attrNames (gatewayOnly servers)
  ) noCallerRenderers;
  invalidCallerRejected =
    let
      invalidRender = callerRenderer.renderServers {
        inherit (gatewayPolicy) enabledServers;
        callerId = "not-registered";
        inherit (gatewayPolicy) callerIds;
        normalize = server: server;
      };
    in
    !(builtins.tryEval (builtins.deepSeq invalidRender true)).success;
  zcodePluginConfigFiles = builtins.filter (name: lib.hasInfix ".zcode/cli/plugins/" name) (
    builtins.attrNames gatewayCfg.home.file
  );
  # The nix-managed always-on profile is deliberately EMPTY. zammad and
  # apple-events left first (~29k tokens between them); fabric, grep and time
  # followed on measured usage — 124/117/54 calls across 1,651 local
  # session logs. A session calling none of them, which is most sessions, paid
  # for their schemas anyway.
  #
  # Asserted as an EXACT SET, not a floor. An empty floor would be vacuously
  # true and would prove nothing; equality fails in both directions, so a
  # server silently re-added to the always-on profile fails the build just as a
  # missing one would. shared-mcp-on-demand-reachable proves everything moved
  # out is still attachable, which is what makes each move a scoping change
  # rather than a capability loss.
  expectedGlobalServers = [ ];
  unexpectedGlobalServers = builtins.filter (
    name: !(builtins.elem name expectedGlobalServers)
  ) cfg.enabledServerNames;
  missingGlobalServers = builtins.filter (
    name: !(builtins.elem name cfg.enabledServerNames)
  ) expectedGlobalServers;

  onDemandNames = cfg.onDemandServers;
  # An on-demand server must be absent from the always-on profile AND rendered
  # to a ready-to-attach file. Absent from both would be a silent capability
  # loss, which is the failure this check exists to prevent.
  onDemandLeaked = builtins.filter (name: builtins.elem name cfg.enabledServerNames) onDemandNames;
  onDemandRenderable = builtins.filter (name: cfg.servers ? ${name}) onDemandNames;
  onDemandUnreachable = builtins.filter (
    name: !(hmConfig.config.home.file ? ".claude/mcp-available/${name}.json")
  ) (builtins.filter (name: cfg.onDemandEnabledServers ? ${name}) onDemandRenderable);
  rendererNames = {
    claude = builtins.attrNames hmConfig.config.programs.claude.mcpServers;
    codex = hmConfig.config.programs.codex.mcpServerNames;
    antigravity-cli = hmConfig.config.programs.antigravity-cli.mcpServerNames;
    antigravity-ide = hmConfig.config.programs.antigravity-ide.mcpServerNames;
    qwen-code = hmConfig.config.programs.qwen-code.mcpServerNames;
    opencode = hmConfig.config.programs.opencode.mcpServerNames;
  };
  rendererMismatches = builtins.filter (name: rendererNames.${name} != cfg.enabledServerNames) (
    builtins.attrNames rendererNames
  );
  callerIdMismatches =
    map (binding: binding.id) callerBindings != map (binding: binding.label) callerBindings;
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
  shared-mcp-global-profile =
    assert
      missingGlobalServers == [ ]
      || throw "Shared MCP profile missing global servers: ${builtins.toJSON missingGlobalServers}; actual=${builtins.toJSON cfg.enabledServerNames}";
    assert
      unexpectedGlobalServers == [ ]
      || throw "Shared MCP profile gained unexpected always-on servers: ${builtins.toJSON unexpectedGlobalServers}. Every server costs tokens in EVERY session; add it to programs.aiMcp.onDemandServers unless it is called in nearly all of them.";
    helpers.mkMarker "check-shared-mcp-global-profile" "Shared MCP profile is exactly the ${toString (builtins.length expectedGlobalServers)} expected always-on servers";

  shared-mcp-on-demand-reachable =
    assert
      onDemandLeaked == [ ]
      || throw "On-demand MCP servers leaked into the always-on profile: ${builtins.toJSON onDemandLeaked}";
    assert
      onDemandRenderable == onDemandNames
      || throw "On-demand MCP servers absent from the catalog entirely: ${builtins.toJSON onDemandNames} vs catalog ${builtins.toJSON onDemandRenderable}";
    assert
      onDemandUnreachable == [ ]
      || throw "On-demand MCP servers unreachable — no ~/.claude/mcp-available file: ${builtins.toJSON onDemandUnreachable}";
    helpers.mkMarker "check-shared-mcp-on-demand-reachable" "On-demand MCP servers are out of the always-on profile and still attachable via ~/.claude/mcp-available";

  shared-mcp-renderer-parity =
    assert
      rendererMismatches == [ ]
      || throw "MCP renderer parity mismatch: ${builtins.toJSON rendererMismatches}; shared=${builtins.toJSON cfg.enabledServerNames}; renderers=${builtins.toJSON rendererNames}";
    helpers.mkMarker "check-shared-mcp-renderer-parity" "Shared MCP renderer parity verified for Claude, Codex, Antigravity CLI/IDE, Qwen, and OpenCode";

  mcp-gateway-caller-identities =
    assert
      gatewayNames != [ ]
      || throw "MCP gateway caller check found no gateway routes to inspect; the fixture is vacuous";
    assert
      callerIdMismatches == false
      || throw "MCP caller IDs do not match their harnesses: ${
        builtins.toJSON (map (binding: { inherit (binding) label id; }) callerBindings)
      }";
    assert
      callerEnvNames == expectedCallerEnvs
      || throw "MCP caller key environment overrides changed without an explicit renderer check: ${builtins.toJSON callerEnvNames}";
    assert
      !callerEnvCollisions
      || throw "MCP caller key environment names must be unique: ${builtins.toJSON callerEnvNames}";
    assert
      badCallerHeaders == [ ]
      || throw "Rendered MCP gateway headers do not reference exactly their own caller key: ${builtins.toJSON badCallerHeaders}";
    assert
      noCallerGatewayRoutes == [ ]
      || throw "A harness without a registered caller ID received gateway routes: ${builtins.toJSON noCallerGatewayRoutes}";
    assert invalidCallerRejected || throw "The shared MCP renderer accepted an unregistered caller ID";
    assert
      !(builtins.pathExists ../../modules/zcode/default.nix) && zcodePluginConfigFiles == [ ]
      || throw "ZCode v3.14.3 only expands ZCODE_* in plugin MCP declarations; keep routes absent until nix-ai has a plugin MCP renderer";
    helpers.mkMarker "check-mcp-gateway-caller-identities" "MCP gateway routes use unique, registry-backed per-harness key references";

  splunk-mcp-gateway-route =
    assert
      cfg.servers.splunk.type == "http" && cfg.servers.splunk.bearer_token_env_var == "SPLUNK_MCP_TOKEN"
      || throw "Splunk MCP must be an http gateway route authenticated by SPLUNK_MCP_TOKEN: ${builtins.toJSON cfg.servers.splunk}";
    helpers.mkMarker "check-splunk-mcp-gateway-route" "Splunk MCP is a gateway route, not a local stdio launcher";

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

  codex-mcp-launch-contract =
    assert
      codexLaunchContractMismatches == [ ]
      || throw "Codex MCP launch contract mismatch: ${builtins.toJSON codexLaunchContractMismatches}";
    helpers.mkMarker "check-codex-mcp-launch-contract" "Codex MCP servers have scoped environment forwarding and 300-second startup/tool timeouts";
}
