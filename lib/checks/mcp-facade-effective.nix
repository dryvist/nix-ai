# Global facade canary, negative, standalone, and frozen-baseline checks.
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
  nativeMcpMaps = import ./mcp-facade-native-maps.nix;
  nativeMcpMapNames = hm: lib.mapAttrs (_: servers: builtins.attrNames servers) (nativeMcpMaps hm);
  nativeMcpMapMismatches =
    hm: expected:
    builtins.filter (name: (nativeMcpMapNames hm).${name} != expected) (
      builtins.attrNames rendererNames
    );
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
  canaryRendererMismatches = builtins.filter (name: canaryRendered.${name} != facadeNames) (
    builtins.attrNames canaryRendered
  );
  canaryOnDemandFiles = builtins.filter (name: lib.hasPrefix ".claude/mcp-available/" name) (
    builtins.attrNames hmConfigFacadeCanary.config.home.file
  );
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
  # module.nix imported alone without agent-skills; the canary option must evaluate there.
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
    entry:
    (entry ? owner)
    && (entry ? cutover)
    && builtins.match "[0-9]{4}-[0-9]{2}-[0-9]{2}" (entry.expiry or "") != null;
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
      nativeMcpMapMismatches hmConfigFacadeCanary facadeNames == [ ]
      || throw "facadeCanary final native MCP maps are not exactly [agent-facade]: ${builtins.toJSON (nativeMcpMapNames hmConfigFacadeCanary)}";
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
      == "printf '{\"X-Agent-Key\":\"%s\"}\\n' \"\${GATEWAY_KEY_CLAUDE_CODE}\""
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
