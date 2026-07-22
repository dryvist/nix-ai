# Nix quality checks - thin aggregator
# Individual check groups live in lib/checks/{lint,claude,agent-skills,codex,antigravity-cli,mcp,mlx,fabric}.nix
{
  pkgs,
  src,
  home-manager,
  aiModule,
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
        wiredLimitMb = 90000;
        standaloneWiredLimitMb = 118000;
      };
    }
  ];
in
(import ./checks/lint.nix { inherit pkgs src; })
// (import ./checks/ai-stack.nix { inherit pkgs testLocalModelId; })
// (import ./checks/claude.nix { inherit pkgs hmConfig; })
// (import ./checks/agent-skills.nix { inherit pkgs hmConfig; })
// (import ./checks/codex.nix { inherit pkgs hmConfig; })
// (import ./checks/qwen-code.nix { inherit pkgs hmConfig; })
// (import ./checks/antigravity-cli.nix { inherit pkgs hmConfig; })
// (import ./checks/mcp.nix { inherit pkgs hmConfig; })
// (import ./checks/autonomous-profile.nix { inherit pkgs; })
// (import ./checks/mlx.nix { inherit pkgs hmConfig; })
// (import ./checks/mlx-watchdog.nix { inherit pkgs src; })
// (import ./checks/mlx-catalog.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-cluster.nix { inherit pkgs hmConfigCluster; })
// (import ./checks/fabric.nix {
  inherit
    pkgs
    hmConfig
    hmConfigFabricServer
    src
    ;
})
