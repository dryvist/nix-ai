# Per-client selector checks: the selected client switches its whole native
# MCP map, while every unselected renderer remains byte-for-byte equivalent.
{
  pkgs,
  hmConfig,
  mkHmConfig,
  rendererNames,
  rendererNamesOf,
  ...
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  facadeGateway = "https://gateway.example.invalid";
  facadeNames = [ "agent-facade" ];
  callerClient = import ../../modules/mcp/client.nix { inherit lib; };
  selectedClientConfig = client: {
    programs.opencode.enable = true;
    programs.aiMcp = {
      gatewayBaseUrl = facadeGateway;
      facadeCanaryClients.${client} = true;
    };
  };
  hmConfigSelectorBaseline = mkHmConfig [
    {
      programs.opencode.enable = true;
      programs.aiMcp.gatewayBaseUrl = facadeGateway;
    }
  ];
  hmConfigClaudeOnly = mkHmConfig [ (selectedClientConfig "claude") ];
  hmConfigCodexOnly = mkHmConfig [ (selectedClientConfig "codex") ];
  hmConfigQwenOnly = mkHmConfig [ (selectedClientConfig "qwen-code") ];
  hmConfigOpenCodeOnly = mkHmConfig [ (selectedClientConfig "opencode") ];
  callerRegistryFixture = "${builtins.toString ../../.}/lib/checks/fixtures/callers-validation-cold-path-proof";
  gatewayLauncherCheck = import ./mcp-gateway-key-launch-hook.nix {
    inherit pkgs mkHmConfig;
  };
  nativeMcpMaps = import ./mcp-facade-native-maps.nix;
  nativeMcpMapNames = hm: lib.mapAttrs (_: servers: builtins.attrNames servers) (nativeMcpMaps hm);
  bridge = lib.getExe (import ../../modules/mcp/mcp-remote.nix { inherit pkgs; });
  expectedFacade = {
    command = bridge;
    args = [
      "${facadeGateway}/agents"
      "--header"
      "X-Agent-Key:\${AGENT_FACADE_KEY}"
    ];
  };
  selectorClaudeServer = hmConfigClaudeOnly.config.programs.claude.mcpServers.agent-facade;
  selectorCodexServer = hmConfigCodexOnly.config.programs.codex.generatedMcpServers.agent-facade;
  selectorQwenServer =
    hmConfigQwenOnly.config.programs.qwen-code.generatedSettings.mcpServers.agent-facade;
  unselectedRendererMismatches =
    hm: selected:
    builtins.filter (
      name:
      name != selected && (nativeMcpMaps hm).${name} != (nativeMcpMaps hmConfigSelectorBaseline).${name}
    ) (builtins.attrNames rendererNames);
  onDemandFiles =
    hm:
    builtins.filter (name: lib.hasPrefix ".claude/mcp-available/" name) (
      builtins.attrNames hm.config.home.file
    );
  selectorNegatives = {
    unknownClient = mkHmConfig [
      {
        programs.aiMcp = {
          gatewayBaseUrl = facadeGateway;
          facadeCanaryClients.unknown-client = true;
        };
      }
    ];
    unsupportedAntigravityIde = mkHmConfig [
      {
        programs.aiMcp = {
          gatewayBaseUrl = facadeGateway;
          facadeCanaryClients.antigravity-ide = true;
        };
      }
    ];
    noGateway = mkHmConfig [ { programs.aiMcp.facadeCanaryClients.claude = true; } ];
    unknownClaudeCaller = mkHmConfig [
      (selectedClientConfig "claude")
      { programs.claude.callerId = lib.mkForce "unregistered-caller"; }
    ];
    malformedClaudeCaller = mkHmConfig [
      (selectedClientConfig "claude")
      { programs.claude.callerId = lib.mkForce "claude-code;invalid"; }
    ];
  };
  standaloneSelectorEvaluates =
    selected:
    let
      standalone = lib.evalModules {
        modules = [
          {
            options.assertions = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [ ];
            };
            config = {
              _module.args.pkgs = pkgs;
              programs.aiMcp = {
                facadeCanaryClients.claude = selected;
                gatewayBaseUrl = if selected then facadeGateway else null;
              };
            };
          }
          ../../modules/mcp/module.nix
        ];
      };
    in
    (builtins.tryEval (
      assert builtins.all (assertion: assertion.assertion) standalone.config.assertions;
      assert selected || standalone.config.programs.aiMcp.callerRegistry == null;
      builtins.deepSeq {
        callerRegistry = standalone.config.programs.aiMcp.callerRegistry;
        keyEnv =
          if selected then
            callerClient.callerKeyEnvFor {
              callerId = "claude-code";
              callerRegistry = standalone.config.programs.aiMcp.callerRegistry;
            }
          else
            null;
      } true
    )).success;
  selectedCallerRendererEvaluates =
    callerId:
    let
      selected = lib.evalModules {
        modules = [
          (
            { config, lib, ... }:
            {
              options = {
                assertions = lib.mkOption {
                  type = lib.types.listOf lib.types.unspecified;
                  default = [ ];
                };
                programs.claude = {
                  callerId = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };
                  excludedMcpServers = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                  mcpServers = lib.mkOption {
                    type = lib.types.attrsOf lib.types.unspecified;
                    default = { };
                  };
                };
              };
              config = {
                _module.args.pkgs = pkgs;
                _module.args."homelab-contracts" = callerRegistryFixture;
                programs.aiMcp = {
                  gatewayBaseUrl = facadeGateway;
                  facadeCanaryClients.claude = true;
                };
                programs.claude = {
                  inherit callerId;
                  mcpServers = (import ../../modules/claude/mcp-render.nix { inherit lib config; }).mcpServers;
                };
              };
            }
          )
          ../../modules/mcp/module.nix
        ];
      };
    in
    (builtins.tryEval (
      assert builtins.all (assertion: assertion.assertion) selected.config.assertions;
      builtins.deepSeq selected.config.programs.claude.mcpServers true
    )).success;
  evaluates =
    hm:
    (builtins.tryEval (
      assert builtins.all (assertion: assertion.assertion) hm.config.assertions;
      builtins.deepSeq {
        enabled = hm.config.programs.aiMcp.enabledServerNames;
        clients = hm.config.programs.aiMcp.facadeCanaryClients;
        rendered = rendererNamesOf hm;
        native = nativeMcpMaps hm;
      } true
    )).success;
in
{
  facade-canary-client-selectors =
    assert
      builtins.all (enabled: !enabled) (
        builtins.attrValues hmConfig.config.programs.aiMcp.facadeCanaryClients
      )
      || throw "per-client facade selectors do not default off";
    assert
      evaluates hmConfigClaudeOnly && evaluates hmConfigCodexOnly && evaluates hmConfigQwenOnly
      || throw "a selected-client positive fixture failed Home Manager assertions";
    assert
      (nativeMcpMapNames hmConfigClaudeOnly).claude == facadeNames
      && hmConfigClaudeOnly.config.programs.claude.mcpServerNames == facadeNames
      && unselectedRendererMismatches hmConfigClaudeOnly "claude" == [ ]
      || throw "Claude selector did not isolate its whole-set facade cutover";
    assert
      onDemandFiles hmConfigClaudeOnly == [ ]
      && hmConfigClaudeOnly.config.programs.claude.settings.enabledMcpjsonServers == [ ]
      && hmConfigClaudeOnly.config.programs.agentSkills.groupMcpServers == { }
      || throw "Claude selector left on-demand approvals, files, or skill-group MCP attachments";
    assert
      selectorClaudeServer.url == "${facadeGateway}/agents"
      &&
        selectorClaudeServer.headersHelper
        == "printf '{\"X-Agent-Key\":\"%s\"}\\n' \"\${GATEWAY_KEY_CLAUDE_CODE}\""
      && !(lib.hasInfix "AGENT_FACADE_KEY" selectorClaudeServer.headersHelper)
      && !(selectorClaudeServer.headers ? "X-Agent-Key")
      || throw "Claude selector did not render exactly the canonical environment-backed facade header";
    assert
      (nativeMcpMapNames hmConfigCodexOnly).codex == facadeNames
      && unselectedRendererMismatches hmConfigCodexOnly "codex" == [ ]
      || throw "Codex selector did not isolate its whole-set facade cutover";
    assert
      onDemandFiles hmConfigCodexOnly == onDemandFiles hmConfigSelectorBaseline
      &&
        hmConfigCodexOnly.config.programs.claude.settings.enabledMcpjsonServers
        == hmConfigSelectorBaseline.config.programs.claude.settings.enabledMcpjsonServers
      &&
        hmConfigCodexOnly.config.programs.agentSkills.groupMcpServers
        == hmConfigSelectorBaseline.config.programs.agentSkills.groupMcpServers
      || throw "Codex selector changed Claude-only on-demand files or group attachments";
    assert
      selectorCodexServer.url == "${facadeGateway}/agents"
      && selectorCodexServer.env_http_headers == { "X-Agent-Key" = "AGENT_FACADE_KEY"; }
      || throw "Codex selector did not render exactly the canonical environment-backed facade header";
    assert
      (nativeMcpMapNames hmConfigQwenOnly)."qwen-code" == facadeNames
      && unselectedRendererMismatches hmConfigQwenOnly "qwen-code" == [ ]
      || throw "Qwen selector did not isolate its whole-set facade cutover";
    assert
      onDemandFiles hmConfigQwenOnly == onDemandFiles hmConfigSelectorBaseline
      &&
        hmConfigQwenOnly.config.programs.claude.settings.enabledMcpjsonServers
        == hmConfigSelectorBaseline.config.programs.claude.settings.enabledMcpjsonServers
      &&
        hmConfigQwenOnly.config.programs.agentSkills.groupMcpServers
        == hmConfigSelectorBaseline.config.programs.agentSkills.groupMcpServers
      || throw "Qwen selector changed Claude-only on-demand files or group attachments";
    assert
      selectorQwenServer == expectedFacade
      || throw "Qwen selector did not render the canonical /agents route through the environment-backed bridge";
    assert
      (nativeMcpMapNames hmConfigOpenCodeOnly).opencode == facadeNames
      && unselectedRendererMismatches hmConfigOpenCodeOnly "opencode" == [ ]
      || throw "OpenCode selector did not render a final singleton facade map";
    assert
      builtins.all (name: !(evaluates selectorNegatives.${name})) (builtins.attrNames selectorNegatives)
      || throw "a selector negative fixture evaluated: ${
        builtins.toJSON (
          builtins.filter (name: evaluates selectorNegatives.${name}) (builtins.attrNames selectorNegatives)
        )
      }";
    assert
      selectedCallerRendererEvaluates "valid-selected"
      || throw "a selected valid caller failed when malformed unselected records were present in the registry fixture";
    assert
      builtins.all (callerId: !(selectedCallerRendererEvaluates callerId)) [
        "claude-code"
        "missing-trust-tier"
        "invalid-trust-tier"
        "extra-field"
      ]
      || throw "a selected caller with a malformed schema-1 registry record rendered a facade";
    assert
      standaloneSelectorEvaluates false && !(standaloneSelectorEvaluates true)
      || throw "a standalone MCP module must render unselected without caller metadata and reject a selected caller without the registry";
    helpers.mkMarker "check-facade-canary-client-selectors" "Selected clients render only the facade in their final native MCP map; unselected clients retain baseline maps and attachments";

  mcp-gateway-key-launch-hook = gatewayLauncherCheck;
}
