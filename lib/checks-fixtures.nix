# Test fixtures for the regression suite in ./checks.nix.
#
# Split out of ./checks.nix to stay under the .file-size.yml ceiling. The seam
# is by responsibility, not by size: this file BUILDS the evaluated
# home-manager configurations the checks assert against, while ./checks.nix
# decides which check groups run and wires each one to the fixtures it needs.
#
# `rec` because the fixtures are layered — mkHmConfig sits on mkHmConfigWith,
# and most hmConfig* sit on mkHmConfig.
{
  pkgs,
  home-manager,
  aiModule,
}:
rec {
  localMlxCatalog = import ../modules/mlx/catalog-data.nix;
  mkMlxRoleModel =
    key:
    let
      entry = localMlxCatalog.${key};
    in
    {
      id = entry.model;
      inherit (entry) concurrency;
    }
    // import ./model-serving.nix {
      catalogEntry = { };
      mlxCatalogEntry = entry;
    };

  # Placeholder physical model id for regression tests. The real value is
  # sourced by consumers (nix-darwin) from AI_MODEL_LOCAL_LLM; tests only need
  # a valid non-empty mlx-community/* string to populate services.aiStack and
  # exercise lib/ai-stack-models.nix (a function since the role registry was
  # parameterized).
  testLocalModelId = "mlx-community/test-model";

  # Shared test module configuration — used by claude, mlx, and fabric regression
  # checks. `userConfig` reaches modules through `_module.args`, which admits
  # exactly one non-default definition, so the maintainer-profile knobs cannot be
  # overridden from an extra module the way an ordinary option can. Taking the
  # extra attrs here instead lets a check evaluate the stack under a different
  # profile (e.g. telemetry on) without a definition conflict.
  mkBaseTestModule = userConfigExtra: {
    _module.args.userConfig = {
      user.fullName = "JacobPEvans";
    }
    // userConfigExtra;
    services.aiStack.defaultLocalModelId = testLocalModelId;
    home = {
      username = "test-user";
      homeDirectory = "/home/test-user";
      stateVersion = "25.11";
    };
  };

  mkHmConfigWith =
    userConfigExtra: extraModules:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        aiModule
        (mkBaseTestModule userConfigExtra)
      ]
      ++ extraModules;
    };

  mkHmConfig = mkHmConfigWith { };

  hmConfig = mkHmConfig [ ];

  # Same stack with the untrusted agent CLIs switched on
  # (lib/checks/untrusted-clis.nix). The checks that pin a particular
  # untrusted CLI's wiring read this fixture; the default one has none.
  hmConfigUntrusted = mkHmConfig [ { programs.ai.untrustedClis.enable = true; } ];

  inherit (import ./checks-fixtures-mcp.nix { inherit mkHmConfig; })
    hmConfigGatewayCallers
    hmConfigMcpLaunchPrefix
    ;

  inherit (import ./checks/qwen-code-fixtures.nix { inherit mkHmConfig; })
    hmConfigQwenRouter
    hmConfigQwenMissingResident
    hmConfigQwenExcludeToolsEmpty
    hmConfigQwenExcludeToolsCustom
    ;

  # oh-my-openagent switched on (lib/checks/oh-my-openagent.nix): with and
  # without the untrusted CLI gate, since omo-senpi needs both and the plugin
  # entry needs only the first.
  hmConfigOhMyOpenagent = mkHmConfig [
    {
      programs.ai.untrustedClis.enable = true;
      programs.ai.ohMyOpenagent.disabled = false;
    }
  ];
  hmConfigOhMyOpenagentTrusted = mkHmConfig [ { programs.ai.ohMyOpenagent.disabled = false; } ];

  hmConfigAgentSkillsShared = mkHmConfig [
    {
      programs.agentSkills.root = "agents";
    }
  ];

  hmConfigVctCli = mkHmConfig [
    {
      programs.vctCli.enable = true;
    }
  ];

  # Second evaluation with fabric REST API LaunchAgent enabled — used by the
  # fabric-launchd positive check (default eval has enableServer = false).
  hmConfigFabricServer = mkHmConfig [ { programs.fabric.enableServer = true; } ];

  inherit (import ./checks-fixtures-mlx.nix { inherit mkHmConfig localMlxCatalog mkMlxRoleModel; })
    hmConfigCatalog
    hmConfigStaticServing
    ;
  inherit (import ./checks-fixtures-mlx-roles.nix { inherit mkHmConfig mkMlxRoleModel; })
    hmConfigSmallRole
    hmConfigDupRole
    hmConfigCluster
    ;
  # Token Meter evaluations cover the canonical disabled option, independent
  # menu-bar/gate switches, and the legacy enable compatibility mapping.
  hmConfigTokenMeter = mkHmConfig [
    {
      programs.token-meter = {
        disabled = false;
        menuBar = true;
        httpsGate = true;
        bindAddress = "127.0.0.1";
      };
    }
  ];
  hmConfigTokenMeterNoMenu = mkHmConfig [
    { programs.token-meter.disabled = false; }
  ];
  hmConfigTokenMeterLegacy = mkHmConfig [
    { programs.token-meter.enable = true; }
  ];
  hmConfigTokenMeterLegacyDisabled = mkHmConfig [
    { programs.token-meter.enable = false; }
  ];
  # Sixth evaluation exercising the session-sync agent (lib/checks/
  # session-sync.nix): also off by default, so the agent only exists here.
  hmConfigSessionSync = mkHmConfig [
    {
      programs.sessionSync = {
        enable = true;
        remote = "peer.example";
      };
    }
  ];
  # Seventh evaluation exercising the session-archive agent (lib/checks/
  # session-archive.nix): also off by default, so the agent only exists here.
  hmConfigSessionArchive = mkHmConfig [
    {
      programs.sessionArchive = {
        enable = true;
        endpoint = "https://example.invalid";
      };
    }
  ];
  inherit (import ./checks-fixtures-litellm.nix { inherit mkHmConfig; })
    hmConfigLitellmLocal
    hmConfigRouter
    ;
}
