# Nix quality checks - thin aggregator
# Individual check groups live in lib/checks/{lint,claude,agent-skills,codex,antigravity-cli,mlx,fabric}.nix
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
in
(import ./checks/lint.nix { inherit pkgs src; })
// (import ./checks/ai-stack.nix { inherit pkgs testLocalModelId; })
// (import ./checks/claude.nix { inherit pkgs hmConfig; })
// (import ./checks/agent-skills.nix { inherit pkgs hmConfig; })
// (import ./checks/codex.nix { inherit pkgs hmConfig; })
// (import ./checks/antigravity-cli.nix { inherit pkgs hmConfig; })
// (import ./checks/autonomous-profile.nix { inherit pkgs; })
// (import ./checks/mlx.nix { inherit pkgs hmConfig; })
// (import ./checks/fabric.nix {
  inherit
    pkgs
    hmConfig
    hmConfigFabricServer
    src
    ;
})
