# Test fixtures for the regression suite in ./checks.nix.
#
# Split out of ./checks.nix to stay under the .file-size.yml ceiling. The seam
# is by responsibility, not by size: this file BUILDS the evaluated
# home-manager configurations the checks assert against, while ./checks.nix
# decides which check groups run and wires each one to the fixtures it needs.
#
# `rec` because the fixtures are layered — mkHmConfig sits on mkHmConfigWith,
# and most hmConfig* sit on mkHmConfig plus judgeModelStub.
{
  pkgs,
  home-manager,
  aiModule,
}:
rec {
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

  # Third evaluation exercising programs.mlx.catalog (lib/checks/mlx.nix
  # mlx-catalog): a server-like selection plus one direct host override that
  # must beat the catalog's mkDefault.
  hmConfigCatalog = mkHmConfig [
    {
      programs.mlx = {
        catalog = {
          qwen35-9b-optiq = {
            class = "swap";
          };
          qwen38-27b = {
            class = "resident";
            roles = [ "goal-judge" ];
          };
          qwen36-optiq.class = "resident";
          # Stock Qwen3.6 sibling, swap-class: enabled so the compiled
          # modelContextWindows carries its declared 65536 window for
          # mlx-catalog.nix to assert. Resident would push the fixture past
          # residentWeightBudgetGb for no added coverage.
          qwen36-35b.class = "swap";
          qwen3-coder-30b.class = "resident";
          gpt-oss-120b.class = "swap";
          qwen3-next-80b = {
            class = "swap";
            tweaks.ttl = 600;
          };
          # Carries an intrinsic proxy concurrencyLimit=1 (metal::malloc under
          # concurrency) — exercises modelConcurrencyLimits compilation.
          qwen3-next-80b-instruct.class = "swap";
          # Vision-language entry: exercises the per-model backend override
          # (catalog `backend` -> modelBackends -> mlx_vlm.server) while the
          # host backend stays mlx-lm for every other model.
          unlimited-ocr = {
            class = "swap";
            tweaks.ttl = 600;
          };
        };
        # Direct host setting on a catalog-managed key must win over the catalog.
        modelFlagOverrides."mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit".cacheMemoryMb = 8192;
      };
    }
  ];

  # Evaluation exercising programs.mlx.defaultModelKey (lib/checks/
  # mlx-default-model.nix): the declared default is one catalog entry, the
  # runtime override re-points it at another — the two-Mac shape where the
  # serving config is shared and only this key differs.
  hmConfigDefaultModel = mkHmConfig [
    {
      programs.mlx = {
        defaultModelKey = "qwen38-27b";
        catalog = {
          qwen38-27b.class = "resident";
          qwen36-35b = {
            class = "resident";
            roles = [ "goal-judge" ];
          };
        };
      };
    }
  ];

  # Two evaluations for the role-registry check (lib/checks/mlx-catalog-roles.nix).
  # The first binds the `small` role to a swap-class entry; the second assigns
  # one role name to two enabled entries, so the uniqueness assertion must come
  # back false. Kept out of hmConfigCatalog so the duplicate case cannot leak
  # into the checks that read that fixture.
  #
  # Both set programs.mlx.judge.model even though the judge stays disabled: the
  # check locates assertions by matching their `message`, and the judge
  # assertion's message interpolates that option, which has no default.
  judgeModelStub.programs.mlx.judge.model = "mlx-community/test-judge-model";
  hmConfigSmallRole = mkHmConfig [
    judgeModelStub
    {
      programs.mlx.catalog = {
        qwen38-27b.class = "resident";
        qwen35-9b-optiq = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];
  hmConfigDupRole = mkHmConfig [
    judgeModelStub
    {
      programs.mlx.catalog = {
        qwen38-27b = {
          class = "resident";
          roles = [ "small" ];
        };
        qwen35-9b-optiq = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];

  # Fourth evaluation exercising programs.mlx.clusterMode as the coordinator
  # (lib/checks/mlx-cluster.nix): rank env contract, watcher wiring, prefetch.
  # judgeModelStub rides along because lib/checks/mlx-cluster-sharding.nix reads
  # this config's `assertions` list, and the judge assertion's message
  # interpolates an option carrying no default — the same reason the role
  # fixtures above carry it.
  hmConfigCluster = mkHmConfig [
    judgeModelStub
    {
      programs.mlx.clusterMode = {
        enable = true;
        role = "coordinator";
        modelCatalogKey = "glm47-reap50";
        # glm4_moe is pipeline-only; the clusterMode assertions now reject
        # tensor-parallel on it, so this fixture must name the real mode.
        shardingMode = "pipeline";
        wiredLimitMb = 90000;
        standaloneWiredLimitMb = 118000;
      };
    }
  ];
  # Fifth evaluation exercising the token-meter HTTPS gate (lib/checks/
  # token-meter.nix): the module is off by default, so the agent only exists here.
  hmConfigTokenMeter = mkHmConfig [
    {
      programs.token-meter = {
        enable = true;
        bindAddress = "127.0.0.1";
      };
    }
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
  # Evaluation with the local LiteLLM proxy enabled. The module is off by
  # default, so without this fixture every `lib.optionalAttrs
  # litellmLocal.enable` branch across the client modules would go unevaluated
  # and a typo in one of them would pass CI.
  hmConfigLitellmLocal = mkHmConfig [
    {
      programs = {
        litellmLocal.enable = true;
        # Local rungs are what give the subagent tier real depth: this host's own
        # models first, the shared router appended automatically as the terminal
        # rung. Declared here so the fallback-tier check asserts against the
        # shape a real host uses, not against an empty chain.
        litellmLocal.localModels = [
          {
            name = "subagent";
            id = "test-local/small-4bit";
            contextWindow = 131072;
          }
          {
            # contextWindow OMITTED on purpose: this rung exercises the
            # derivation from `mlx.modelContextWindows` below. Without a rung
            # that leaves it null, the suite could only ever prove the
            # hand-written path and would pass unchanged if the derivation were
            # deleted.
            name = "subagent-local2";
            id = "test-local/tiny-4bit";
          }
        ];
        # The catalog side of that derivation. Keyed by physical model id, the
        # same shape options-catalog.nix builds from real entries.
        mlx.modelContextWindows = {
          "test-local/tiny-4bit" = 32768;
        };
      };
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://llm.example.invalid/v1";
        llmEndpointTokenFile = "/run/secrets/LLM_ROUTER_BEARER";
      };
    }
  ];
}
