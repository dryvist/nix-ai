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
  hmConfigFacadeCanary = mkHmConfig [
    {
      programs.aiMcp = {
        facadeCanary = true;
        gatewayBaseUrl = facadeGateway;
      };
    }
  ];
  canaryCfg = hmConfigFacadeCanary.config.programs.aiMcp;
  canaryRendered = rendererNamesOf hmConfigFacadeCanary;
  canaryRendererMismatches = builtins.filter (name: canaryRendered.${name} != facadeNames) (
    builtins.attrNames canaryRendered
  );
  canaryOnDemandFiles = builtins.filter (name: lib.hasPrefix ".claude/mcp-available/" name) (
    builtins.attrNames hmConfigFacadeCanary.config.home.file
  );
  # home-manager throws on any failed assertion once config is read, so an
  # evaluation that throws is the failure (same pattern as litellm-local-negative).
  evaluates =
    hm: (builtins.tryEval (builtins.deepSeq hm.config.programs.aiMcp.enabledServerNames true)).success;
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
