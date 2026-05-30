# Nix quality checks - thin aggregator
# Individual check groups live in lib/checks/{lint,claude,agent-skills,codex,gemini,mlx,fabric}.nix
# PAL package/script checks live in the MCP sub-flake (modules/mcp/checks.nix).
{
  pkgs,
  src,
  home-manager,
  aiModule,
  pal-mcp-server,
}:
let
  # Shared test module configuration — used by claude, mlx, and fabric regression checks
  hmConfig = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      aiModule
      {
        _module.args.userConfig = {
          ai.claudeSchemaUrl = "https://json.schemastore.org/claude-code-settings.json";
          user.fullName = "JacobPEvans";
        };
        home = {
          username = "test-user";
          homeDirectory = "/home/test-user";
          stateVersion = "25.11";
        };
      }
    ];
  };

  # Second evaluation with fabric REST API LaunchAgent enabled — used by the
  # fabric-launchd positive check (default eval has enableServer = false).
  hmConfigFabricServer = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      aiModule
      {
        _module.args.userConfig = {
          ai.claudeSchemaUrl = "https://json.schemastore.org/claude-code-settings.json";
          user.fullName = "JacobPEvans";
        };
        home = {
          username = "test-user";
          homeDirectory = "/home/test-user";
          stateVersion = "25.11";
        };
        programs.fabric.enableServer = true;
      }
    ];
  };
in
(import ./checks/lint.nix { inherit pkgs src; })
// (import ./checks/ai-stack.nix { inherit pkgs; })
// (import ./checks/claude.nix { inherit pkgs hmConfig; })
// (import ./checks/agent-skills.nix { inherit pkgs hmConfig; })
// (import ./checks/codex.nix { inherit pkgs hmConfig; })
// (import ./checks/gemini.nix { inherit pkgs hmConfig; })
// (import ./checks/mlx.nix { inherit pkgs hmConfig; })
// (import ../modules/mcp/checks.nix { inherit pkgs pal-mcp-server; })
// (import ./checks/fabric.nix {
  inherit
    pkgs
    hmConfig
    hmConfigFabricServer
    src
    ;
})
