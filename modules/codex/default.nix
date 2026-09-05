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
  llm-agents,
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
      # One owner per host. Codex ships several releases a week, faster than a
      # relock-and-rebuild cycle can follow.
      #
      #   darwin: null — the `codex` Homebrew cask owns the binary, declared in
      #     lib/homebrew.nix, upgraded by `brew upgrade` with no Nix round trip.
      #     This also restores the stable TCC paths the cask originally gave us:
      #     a Nix store path changes on every bump, so macOS re-prompts for
      #     permissions.
      #   Linux: llm-agents.nix, which has no Homebrew and tracks upstream far
      #     more closely than nixpkgs (0.153.4 against 26.05's 0.146.0).
      #
      # `enable` stays true either way — only the binary is skipped. Everything
      # below (config.toml, MCP wiring, execpolicy, context) is still rendered.
      #
      # This is a definition, not the option's default, and that matters: drop
      # it and home-manager falls back to `pkgs.codex`, silently reinstalling a
      # second, older codex next to the cask.
      package = lib.mkDefault (
        if pkgs.stdenv.hostPlatform.isDarwin then
          null
        else
          llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
      );
      context = lib.mkDefault (builtins.readFile "${ai-assistant-instructions}/AGENTS.md");
      # config.toml is managed via home.activation — do NOT set settings here.
    };

    # Ensure directory structure exists
    home.file.".codex/.keep".text = ''
      # Managed by Nix - programs.codex module
    '';
  };
}
