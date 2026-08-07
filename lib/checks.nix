# Nix quality checks - thin aggregator
# Individual check groups live in lib/checks/{lint,claude,agent-skills,codex,antigravity-cli,mcp,mlx,fabric}.nix
{
  pkgs,
  src,
  home-manager,
  aiModule,
  renderAutonomous,
}:
let
  # Placeholder physical model id for regression tests. The real value is
  # sourced by consumers (nix-darwin) from AI_MODEL_LOCAL_LLM; tests only need
  # a valid non-empty mlx-community/* string to populate services.aiStack and
  # exercise lib/ai-stack-models.nix (a function since the role registry was
  # parameterized).
  testLocalModelId = "mlx-community/test-model";

  # Shared test module configuration — used by claude, mlx, and fabric regression checks
  baseTestModule = {
    _module.args.userConfig = {
      user.fullName = "JacobPEvans";
    };
    services.aiStack.defaultLocalModelId = testLocalModelId;
    home = {
      username = "test-user";
      homeDirectory = "/home/test-user";
      stateVersion = "25.11";
    };
  };

  mkHmConfig =
    extraModules:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        aiModule
        baseTestModule
      ]
      ++ extraModules;
    };

  hmConfig = mkHmConfig [ ];

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
          qwen36-27b-mxfp4 = {
            class = "resident";
            roles = [ "goal-judge" ];
          };
          qwen36-optiq.class = "resident";
          qwen3-coder-30b.class = "resident";
          gpt-oss-120b.class = "swap";
          qwen3-next-80b = {
            class = "swap";
            tweaks.ttl = 600;
          };
          # Carries an intrinsic proxy concurrencyLimit=1 (metal::malloc under
          # concurrency) — exercises modelConcurrencyLimits compilation.
          qwen3-next-80b-instruct.class = "swap";
        };
        # Direct host setting on a catalog-managed key must win over the catalog.
        modelFlagOverrides."mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit".cacheMemoryMb = 8192;
      };
    }
  ];

  # Fourth evaluation exercising programs.mlx.clusterMode as the coordinator
  # (lib/checks/mlx-cluster.nix): rank env contract, watcher wiring, prefetch.
  hmConfigCluster = mkHmConfig [
    {
      programs.mlx.clusterMode = {
        enable = true;
        role = "coordinator";
        modelCatalogKey = "glm47-reap50";
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
in
(import ./checks/lint.nix { inherit pkgs src; })
// (import ./checks/token-meter.nix {
  inherit
    pkgs
    src
    hmConfig
    hmConfigTokenMeter
    ;
})
// (import ./checks/session-sync.nix {
  inherit
    pkgs
    hmConfig
    hmConfigSessionSync
    ;
})
// (import ./checks/ai-stack.nix { inherit pkgs testLocalModelId; })
// (import ./checks/ai-stack-endpoint.nix { inherit pkgs; })
// (import ./checks/claude.nix { inherit pkgs hmConfig; })
// (import ./checks/agent-skills.nix { inherit pkgs hmConfig; })
// (import ./checks/codex.nix { inherit pkgs hmConfig; })
// (import ./checks/qwen-code.nix { inherit pkgs hmConfig; })
// (import ./checks/antigravity-cli.nix { inherit pkgs hmConfig; })
// (import ./checks/mcp.nix { inherit pkgs hmConfig; })
// (import ./checks/autonomous-profile.nix {
  inherit pkgs;
  render = renderAutonomous;
})
// (import ./checks/mlx.nix { inherit pkgs hmConfig; })
// (import ./checks/mlx-single-model.nix { inherit pkgs src; })
// (import ./checks/mlx-bash32.nix { inherit pkgs hmConfig src; })
// (import ./checks/mlx-watchdog.nix { inherit pkgs src; })
// (import ./checks/mlx-worker-reap.nix { inherit pkgs hmConfig src; })
// (import ./checks/mlx-warmup.nix { inherit pkgs src; })
// (import ./checks/mlx-catalog.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-harmony.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-cluster.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-peer-env.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-pd-env.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-pd-callsites.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-mem-headroom.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-scripts.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-selfheal.nix { inherit pkgs src; })
// (import ./checks/fabric.nix {
  inherit
    pkgs
    hmConfig
    hmConfigFabricServer
    src
    ;
})
