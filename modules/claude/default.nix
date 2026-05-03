# Unified Claude Code Configuration Module
#
# This module consolidates all Claude Code configuration into a single
# declarative interface: plugins, commands, agents, skills, hooks, MCP servers.
#
# Features:
# - Declarative plugin management via flake inputs
# - Hybrid mode: Nix-managed baseline + runtime /plugin install
# - Cross-platform: Works on Darwin, NixOS, standalone home-manager
# - Generates settings.json (known_marketplaces.json managed by Claude Code at runtime)
#
# Usage:
#   programs.claude = {
#     enable = true;
#     plugins.enabled = { "commit-commands@anthropics/claude-code" = true; };
#   };
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude;
in
{
  imports = [
    ./options.nix
    ./registry.nix
    ./plugins.nix
    ./components.nix
    ./settings.nix
    ./statusline
    # Note: MCP server configuration is handled in settings.nix via the `mcpServers` option.
    ./orphan-cleanup.nix
    # PAL/MCP runtime moved to ../mcp/module.nix (sub-flake) — imported from
    # modules/default.nix so it's available regardless of which AI tool is enabled.
  ];

  config = lib.mkIf cfg.enable {
    # Note: apiKeyHelper now reads config from ~/.config/bws/.env
    # The Python helper (bws_helper.py) will give clear errors if config is missing

    # Ensure ~/.claude directory structure exists
    # Individual sub-modules populate these directories
    home.file = {
      ".claude/.keep".text = ''
        # Managed by Nix - programs.claude module
      '';
      ".claude/plugins/.keep".text = ''
        # Plugin registry managed by Nix
      '';
    }
    // lib.optionalAttrs cfg.apiKeyHelper.enable {
      # API Key Helper script for headless authentication
      # Configuration now comes from ~/.config/bws/.env (not Nix options)
      "${cfg.apiKeyHelper.scriptPath}" = {
        source = ./get-api-key.py; # Python script using bws_helper
        executable = true;
      };

      # Shared BWS helper used by get-api-key.py to fetch CLAUDE_OAUTH_TOKEN
      # from ~/.config/bws/.env (Bitwarden Secrets Manager backend).
      ".claude/scripts/bws_helper.py" = {
        source = ./bws_helper.py;
        executable = true;
      };

      # Template for ~/.config/bws/.env that bws_helper.py reads
      ".config/bws/.env.example" = {
        source = ./bws-env.example;
      };
    };

    # Activation scripts for directory and config setup
    # NOTE: "local" marketplace setup removed - Claude Code doesn't use it by default.
    # See docs/CLAUDE-MARKETPLACE-ARCHITECTURE.md for details.
    home.activation = {
      # WakaTime config — fetches API key from Doppler at activation time.
      # Graceful fallback: keeps existing config if Doppler is unreachable.
      wakatimeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -n "$DRY_RUN_CMD" ]; then
          echo "wakatime: dry-run — skipping Doppler fetch" >&2
        elif WAKA_KEY=$(${pkgs.doppler}/bin/doppler secrets get WAKATIME_API_KEY \
          -p ai-ci-automation -c prd --plain 2>/dev/null); then
          (umask 077; printf '[settings]\napi_key = %s\nwrites_only = false\n' "$WAKA_KEY" \
            > "${config.home.homeDirectory}/.wakatime.cfg")
        else
          echo "wakatime: Doppler unreachable — keeping existing config" >&2
        fi
      '';
    };
  };
}
