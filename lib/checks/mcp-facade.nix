# Facade canary and non-canary baseline checks. Merged into the output of
# ./mcp.nix; split out for the per-file size gate.
#
# Each negative fixture is a real home-manager evaluation that must fail to
# evaluate; a check that accepts one fails. The baseline negative is a predicate.
{
  pkgs,
  hmConfig,
  mkHmConfig,
  rendererNames,
  rendererNamesOf,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  facadeGateway = "https://gateway.example.invalid";
  facadeNames = [ "agent-facade" ];
  selectedClientConfig = client: {
    programs.aiMcp = {
      gatewayBaseUrl = facadeGateway;
      facadeCanaryClients.${client} = true;
    };
  };
  hmConfigSelectorBaseline = mkHmConfig [ { programs.aiMcp.gatewayBaseUrl = facadeGateway; } ];
  hmConfigClaudeOnly = mkHmConfig [ (selectedClientConfig "claude") ];
  hmConfigCodexOnly = mkHmConfig [ (selectedClientConfig "codex") ];
  hmConfigQwenOnly = mkHmConfig [ (selectedClientConfig "qwen-code") ];
  hmConfigFacadeCanary = mkHmConfig [
    {
      programs.opencode.enable = true;
      programs.aiMcp = {
        facadeCanary = true;
        facadeCanaryClients.codex = true;
        gatewayBaseUrl = facadeGateway;
      };
    }
  ];
  canaryCfg = hmConfigFacadeCanary.config.programs.aiMcp;
  canaryRendered = rendererNamesOf hmConfigFacadeCanary;
  canaryOpencode =
    builtins.fromJSON
      hmConfigFacadeCanary.config.home.file."${hmConfigFacadeCanary.config.programs.opencode.configDir}/opencode.json".source.json;
  canaryOpencodeHeaders = canaryOpencode.mcp.agent-facade.headers;
  canaryCodex = hmConfigFacadeCanary.config.programs.codex.generatedMcpServers.agent-facade;
  bridge = lib.getExe (import ../../modules/mcp/mcp-remote.nix { inherit pkgs; });
  expectedFacade = {
    command = bridge;
    args = [
      "${facadeGateway}/agents"
      "--header"
      "X-Agent-Key:\${AGENT_FACADE_KEY}"
    ];
  };
  agyFacade =
    hmConfigFacadeCanary.config.programs.antigravity-cli.generatedSettings.mcpServers.agent-facade;
  qwenFacade =
    hmConfigFacadeCanary.config.programs.qwen-code.generatedSettings.mcpServers.agent-facade;
  selectorClaudeServer = hmConfigClaudeOnly.config.programs.claude.mcpServers.agent-facade;
  selectorCodexServer = hmConfigCodexOnly.config.programs.codex.generatedMcpServers.agent-facade;
  selectorQwenServer =
    hmConfigQwenOnly.config.programs.qwen-code.generatedSettings.mcpServers.agent-facade;
  canaryRendererMismatches = builtins.filter (name: canaryRendered.${name} != facadeNames) (
    builtins.attrNames canaryRendered
  );
  canaryOnDemandFiles = builtins.filter (name: lib.hasPrefix ".claude/mcp-available/" name) (
    builtins.attrNames hmConfigFacadeCanary.config.home.file
  );
  onDemandFiles =
    hm:
    builtins.filter (name: lib.hasPrefix ".claude/mcp-available/" name) (
      builtins.attrNames hm.config.home.file
    );
  selectorRenderers = {
    claude = rendererNamesOf hmConfigClaudeOnly;
    codex = rendererNamesOf hmConfigCodexOnly;
    qwen-code = rendererNamesOf hmConfigQwenOnly;
  };
  unselectedRendererMismatches =
    hm: selected:
    builtins.filter (
      name:
      name != selected
      && (rendererNamesOf hm).${name} != (rendererNamesOf hmConfigSelectorBaseline).${name}
    ) (builtins.attrNames rendererNames);
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
  };
  # Force Home Manager assertions as well as the rendered outputs: otherwise
  # tryEval can accept a config whose assertion list contains false entries.
  evaluates =
    hm:
    (builtins.tryEval (
      assert builtins.all (assertion: assertion.assertion) hm.config.assertions;
      builtins.deepSeq {
        enabled = hm.config.programs.aiMcp.enabledServerNames;
        clients = hm.config.programs.aiMcp.facadeCanaryClients;
        rendered = rendererNamesOf hm;
      } true
    )).success;
  facadeNegatives = {
    rawCatalogEntry = mkHmConfig [
      {
        programs.aiMcp = {
          facadeCanary = true;
          gatewayBaseUrl = facadeGateway;
          servers.exa.disabled = lib.mkForce false;
        };
      }
    ];
    extraOnDemandEntry = mkHmConfig [
      {
        programs.aiMcp = {
          facadeCanary = true;
          gatewayBaseUrl = facadeGateway;
          extraOnDemandMcpServers.http-test = {
            type = "http";
            url = "https://example.invalid/mcp";
          };
        };
      }
    ];
    noGateway = mkHmConfig [ { programs.aiMcp.facadeCanary = true; } ];
  };
  facadeBaseline = import ../../modules/mcp/facade-baseline.nix;
  baselineNames = builtins.attrNames facadeBaseline;
  # Names a non-canary consumer reaches that the baseline does not allow.
  baselineAdditions =
    hm:
    builtins.filter (name: !(facadeBaseline ? ${name})) (
      hm.config.programs.aiMcp.enabledServerNames
      ++ builtins.attrNames hm.config.programs.aiMcp.onDemandEnabledServers
    );
  hmConfigBaselineAddition = mkHmConfig [
    {
      programs.aiMcp.extraOnDemandMcpServers.not-in-baseline = {
        type = "http";
        url = "https://example.invalid/mcp";
      };
    }
  ];
  # module.nix imported alone (flake/home-manager-modules.nix exports module sets
  # without agent-skills); the canary option must evaluate there.
  standaloneNames =
    enable:
    (lib.evalModules {
      modules = [
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf lib.types.unspecified;
            default = [ ];
          };
          config = {
            _module.args.pkgs = pkgs;
            programs.aiMcp = {
              facadeCanary = enable;
              gatewayBaseUrl = if enable then facadeGateway else null;
            };
          };
        }
        ../../modules/mcp/module.nix
      ];
    }).config.programs.aiMcp.enabledServerNames;
  baselineWellFormed =
    e:
    (e ? owner)
    && (e ? cutover)
    && builtins.match "[0-9]{4}-[0-9]{2}-[0-9]{2}" (e.expiry or "") != null;
in
{
  facade-canary-effective-set =
    assert
      canaryRendererMismatches == [ ]
      || throw "facadeCanary renderers not exactly [agent-facade]: ${
        builtins.toJSON (
          map (name: {
            inherit name;
            names = canaryRendered.${name};
          }) canaryRendererMismatches
        )
      }";
    assert
      canaryCfg.enabledServerNames == facadeNames
      || throw "facadeCanary enabled set is not [agent-facade]: ${builtins.toJSON canaryCfg.enabledServerNames}";
    assert
      builtins.attrNames canaryCfg.onDemandEnabledServers == [ ]
      || throw "facadeCanary rendered on-demand servers: ${builtins.toJSON (builtins.attrNames canaryCfg.onDemandEnabledServers)}";
    assert
      canaryOnDemandFiles == [ ]
      || throw "facadeCanary rendered on-demand files: ${builtins.toJSON canaryOnDemandFiles}";
    assert
      hmConfigFacadeCanary.config.programs.agentSkills.groupMcpServers == { }
      || throw "facadeCanary left agent-skill group attachments: ${builtins.toJSON hmConfigFacadeCanary.config.programs.agentSkills.groupMcpServers}";
    assert
      canaryCfg.servers.agent-facade.env_http_headers."X-Agent-Key" == "AGENT_FACADE_KEY"
      || throw "facadeCanary agent-facade lost its Codex key header mapping";
    assert
      canaryCfg.facadeServer.url == "${facadeGateway}/agents"
      && canaryCfg.facadeServer.env_http_headers == { "X-Agent-Key" = "AGENT_FACADE_KEY"; }
      || throw "facadeCanary did not select the canonical /agents route and key environment reference";
    assert
      canaryCodex.url == "${facadeGateway}/agents"
      && canaryCodex.env_http_headers == { "X-Agent-Key" = "AGENT_FACADE_KEY"; }
      || throw "Codex facade route lost its environment-backed header";
    assert
      canaryOpencodeHeaders."X-Agent-Key" == "{env:AGENT_FACADE_KEY}"
      || throw "facadeCanary OpenCode agent-facade lost its environment key header";
    assert
      builtins.all (value: !(lib.hasInfix "\${" value)) (builtins.attrValues canaryOpencodeHeaders)
      || throw "facadeCanary OpenCode agent-facade contains an unexpanded header";
    assert
      hmConfigFacadeCanary.config.programs.claude.mcpServers.agent-facade.headersHelper
      == "printf '{\"X-Agent-Key\":\"%s\"}\\n' \"\${AGENT_FACADE_KEY}\""
      || throw "facadeCanary agent-facade lost its Claude key headersHelper";
    assert
      !(hmConfigFacadeCanary.config.programs.claude.mcpServers.agent-facade.headers ? "X-Agent-Key")
      || throw "facadeCanary agent-facade retained its static Claude key header";
    assert
      agyFacade == expectedFacade
      || throw "Antigravity facade bridge config differs: ${builtins.toJSON agyFacade}";
    assert
      qwenFacade == expectedFacade
      || throw "Qwen facade bridge config differs: ${builtins.toJSON qwenFacade}";
    helpers.mkMarker "check-facade-canary-effective-set" "facadeCanary: every renderer, on-demand file and agent-skill attachment names exactly agent-facade";

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
      selectorRenderers.claude.claude == facadeNames
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
        == "printf '{\"X-Agent-Key\":\"%s\"}\\n' \"\${AGENT_FACADE_KEY}\""
      && !(selectorClaudeServer.headers ? "X-Agent-Key")
      || throw "Claude selector did not render exactly the canonical environment-backed facade header";
    assert
      selectorRenderers.codex.codex == facadeNames
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
      selectorRenderers."qwen-code"."qwen-code" == facadeNames
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
      builtins.all (name: !(evaluates selectorNegatives.${name})) (builtins.attrNames selectorNegatives)
      || throw "a selector negative fixture evaluated: ${
        builtins.toJSON (
          builtins.filter (name: evaluates selectorNegatives.${name}) (builtins.attrNames selectorNegatives)
        )
      }";
    helpers.mkMarker "check-facade-canary-client-selectors" "A selected client alone renders the canonical facade, while other renderers and attachments retain baseline MCP sets";

  facade-canary-renderer-coverage =
    assert
      builtins.attrNames canaryRendered == builtins.attrNames rendererNames
      && builtins.length (builtins.attrNames canaryRendered) == 6
      || throw "facadeCanary reaches ${toString (builtins.length (builtins.attrNames canaryRendered))} renderers; the shared set has ${toString (builtins.length (builtins.attrNames rendererNames))}";
    helpers.mkMarker "check-facade-canary-renderer-coverage" "facadeCanary reaches all 6 shared renderers";

  facade-canary-negatives =
    assert
      evaluates hmConfigFacadeCanary || throw "facadeCanary positive fixture fails its own assertions";
    assert
      builtins.all (name: !(evaluates facadeNegatives.${name})) (builtins.attrNames facadeNegatives)
      || throw "a facadeCanary negative fixture evaluated: ${
        builtins.toJSON (
          builtins.filter (name: evaluates facadeNegatives.${name}) (builtins.attrNames facadeNegatives)
        )
      }";
    helpers.mkMarker "check-facade-canary-negatives" "facadeCanary fails for a raw catalog entry, an extraOnDemandMcpServers entry and a missing gatewayBaseUrl";

  facade-canary-standalone =
    assert
      standaloneNames true == facadeNames
      || throw "module.nix alone: facadeCanary enabled set is ${builtins.toJSON (standaloneNames true)}";
    assert
      standaloneNames false == [ ]
      || throw "module.nix alone: a non-canary consumer reaches ${builtins.toJSON (standaloneNames false)}";
    helpers.mkMarker "check-facade-canary-standalone" "module.nix evaluates alone, with and without facadeCanary";

  facade-baseline =
    assert
      baselineAdditions hmConfig == [ ]
      || throw "non-canary consumer reaches names outside modules/mcp/facade-baseline.nix: ${builtins.toJSON (baselineAdditions hmConfig)}";
    assert
      builtins.all (name: baselineWellFormed facadeBaseline.${name}) baselineNames
      || throw "facade-baseline.nix entries need owner, expiry (YYYY-MM-DD) and cutover";
    assert
      builtins.all (name: hmConfig.config.programs.aiMcp.servers ? ${name}) baselineNames
      || throw "facade-baseline.nix names a server that is not in the catalog";
    assert
      baselineAdditions hmConfigBaselineAddition != [ ]
      || throw "the baseline check accepted a non-canary addition outside the baseline";
    helpers.mkMarker "check-facade-baseline" "Non-canary consumers reach only the ${toString (builtins.length baselineNames)} names in facade-baseline.nix; an addition fails";
}
