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

  # A per-server launchPrefix plus a launchPrefixFor hook
  # (lib/checks/mcp.nix mcp-launch-prefix).
  hmConfigMcpLaunchPrefix = mkHmConfig [
    (
      { lib, ... }:
      {
        programs.aiMcp = {
          launchPrefixFor = vars: [ "/test/injector" ] ++ vars ++ [ "--" ];
          servers = {
            zammad.launchPrefix = [
              "/test/wrapper"
              "--flag"
              "--"
            ];
            vikunja.disabled = lib.mkForce false;
          };
          # A consumer appending one name, exactly as a host does, must keep
          # the curated list (lib/checks/mcp.nix mcp-on-demand-merge).
          onDemandServers = lib.mkAfter [ "vikunja" ];
          extraOnDemandMcpServers.http-test = {
            type = "http";
            url = "https://example.invalid/mcp";
            bearer_token_env_var = "TEST_TOKEN";
          };
        };
        programs.codex.onDemandMcpServers = [ "http-test" ];
      }
    )
  ];

  hmConfigVctCli = mkHmConfig [
    {
      programs.vctCli.enable = true;
    }
  ];

  # Second evaluation with fabric REST API LaunchAgent enabled — used by the
  # fabric-launchd positive check (default eval has enableServer = false).
  hmConfigFabricServer = mkHmConfig [ { programs.fabric.enableServer = true; } ];

  # Third evaluation exercising programs.mlx.catalog (lib/checks/mlx.nix
  # mlx-catalog): a server-like selection plus one direct host override that
  # must beat the catalog's mkDefault.
  hmConfigCatalog = mkHmConfig [
    {
      programs.mlx = {
        catalog = {
          qwen38-27b = {
            class = "resident";
            roles = [ "judge" ];
          };
          # Swap-class text entry exercises its default ttl and model concurrency.
          mimo-9b.class = "swap";
          # OCR stays in the pinned role map and exercises the VLM backend.
          unlimited-ocr = {
            class = "swap";
            tweaks.ttl = 600;
          };
        };
        # Direct host setting on a catalog-managed key must win over the catalog.
        modelFlagOverrides."mlx-community/Qwen3.8-27B-4bit".cacheMemoryMb = 8192;
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];

  # The MacBook production static-resident shape: both resident catalog
  # entries, the stable role mapping, and no swap-class selection.
  hmConfigStaticServing = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        staticResidentLocalProxyConsumers = true;
        memoryHardLimitGb = 46;
        roleMap = {
          models = {
            qwen38-27b = mkMlxRoleModel "qwen38-27b";
            mimo-9b = mkMlxRoleModel "mimo-9b";
          };
          roles = {
            default.model = "qwen38-27b";
            fast.model = "mimo-9b";
            judge.model = "mimo-9b";
            recorder.model = "mimo-9b";
            cheap.model = "mimo-9b";
            small.model = "mimo-9b";
          };
          hosts.workstation = {
            resident = [
              "qwen38-27b"
              "mimo-9b"
            ];
            swap = [ ];
          };
        };
        catalog = {
          qwen38-27b = {
            class = "resident";
            roles = [ "default" ];
          };
          mimo-9b = {
            class = "resident";
            roles = [
              "fast"
              "judge"
              "recorder"
              "cheap"
              "small"
            ];
          };
        };
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];

  # Two evaluations for the role-registry check (lib/checks/mlx-catalog-roles.nix).
  # The first binds the `small` role to a swap-class entry; the second assigns
  # one role name to two enabled entries, so the uniqueness assertion must come
  # back false. Kept out of hmConfigCatalog so the duplicate case cannot leak
  # into the checks that read that fixture.
  hmConfigSmallRole = mkHmConfig [
    {
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
      programs.mlx.catalog = {
        qwen38-27b.class = "resident";
        mimo-9b = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];
  hmConfigDupRole = mkHmConfig [
    {
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
      programs.mlx.catalog = {
        qwen38-27b = {
          class = "resident";
          roles = [ "small" ];
        };
        mimo-9b = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];

  # Fourth evaluation exercising programs.mlx.clusterMode as the coordinator
  # (lib/checks/mlx-cluster.nix): rank env contract, watcher wiring, and the
  # catalog-rendered resident stop list.
  hmConfigCluster = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        roleMap = {
          models = {
            qwen38-27b = mkMlxRoleModel "qwen38-27b";
            mimo-9b = mkMlxRoleModel "mimo-9b";
          };
          roles = {
            default.model = "qwen38-27b";
            fast.model = "mimo-9b";
          };
          hosts.workstation = {
            resident = [
              "qwen38-27b"
              "mimo-9b"
            ];
            swap = [ ];
          };
        };
        catalog = {
          qwen38-27b = {
            class = "resident";
            roles = [ "default" ];
          };
          mimo-9b = {
            class = "resident";
            roles = [ "fast" ];
          };
        };
        clusterMode = {
          enable = true;
          role = "coordinator";
          modelCatalogKey = "glm47-reap50";
          # glm4_moe is pipeline-only; the clusterMode assertions now reject
          # tensor-parallel on it, so this fixture must name the real mode.
          shardingMode = "pipeline";
          wiredLimitMb = 90000;
          standaloneWiredLimitMb = 118000;
        };
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
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
  inherit (import ./checks-fixtures-litellm.nix { inherit mkHmConfig; }) hmConfigLitellmLocal;
}
