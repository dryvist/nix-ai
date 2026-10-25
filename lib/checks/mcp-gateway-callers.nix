# MCP gateway caller identity regression tests
{
  pkgs,
  hmConfig,
  hmConfigMcpLaunchPrefix,
  hmConfigGatewayCallers,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
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
  callerIdMismatches =
    map (binding: binding.id) callerBindings != map (binding: binding.label) callerBindings;
in
{
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

}
