# Codex CLI Configuration Module
#
# Declarative configuration for OpenAI Codex CLI.
# Generates config.toml with shared MCP servers, permissions,
# and project trust levels.
#
# Features:
# - Shared MCP server definitions (filtered for Codex compatibility)
# - Execpolicy rules file from shared permissions
# - config.toml deep-merge activation (preserves runtime state)
{
  config,
  lib,
  pkgs,
  ai-assistant-instructions,
  ...
}:

let
  cfg = config.programs.codex;
in
{
  imports = [
    ./options.nix
    ./settings.nix
  ];

  config = lib.mkIf cfg.enable {
    programs.codex = {
      # nixpkgs packages codex for both supported systems (26.05 ships 0.146).
      # This used to be the `codex` Homebrew cask, chosen for stable TCC paths
      # on macOS — a Nix store path changes on every version bump, so watch for
      # macOS re-prompting for permissions after an upgrade. That tradeoff is
      # deliberate: the cask had no Linux path, which is what pinned the whole
      # stack to the MacBook.
      package = lib.mkDefault pkgs.codex;
      context = lib.mkDefault (builtins.readFile "${ai-assistant-instructions}/AGENTS.md");
      # config.toml is managed via home.activation — do NOT set settings here.
    };

    # Ensure directory structure exists
    home.file.".codex/.keep".text = ''
      # Managed by Nix - programs.codex module
    '';
  };
}
