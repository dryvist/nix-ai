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

  # Bundle get-api-key.py + bws_helper.py into a single Nix store directory
  # so Path(__file__).parent in get-api-key.py resolves bws_helper correctly.
  apiKeyHelperSrc = pkgs.runCommand "claude-api-key-helper-src" { } ''
    mkdir -p $out
    cp ${./get-api-key.py} $out/get-api-key.py
    cp ${./bws_helper.py} $out/bws_helper.py
  '';

  # Wrap get-api-key.py as a self-contained shell app.
  # runtimeInputs injects python314+keyring into PATH only when the wrapper
  # runs — this avoids adding a python3.withPackages env to home.packages,
  # which conflicts with nix-home's python3-3.14-env in buildEnv.
  apiKeyHelperBin = pkgs.writeShellApplication {
    name = "claude-api-key-helper";
    runtimeInputs = [
      (pkgs.python314.withPackages (ps: [ ps.keyring ]))
      pkgs.bws
    ];
    text = ''
      exec python3 ${apiKeyHelperSrc}/get-api-key.py "$@"
    '';
  };
in
{
  imports = [
    ./options-runtime.nix
    ./options-content.nix
    ./options-events.nix
    ./options-settings.nix
    ./options-features.nix
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

    home = {
      # Ensure ~/.claude directory structure exists
      # Individual sub-modules populate these directories
      file = {
        ".claude/.keep".text = ''
          # Managed by Nix - programs.claude module
        '';
        ".claude/plugins/.keep".text = ''
          # Plugin registry managed by Nix
        '';
      }
      // lib.optionalAttrs cfg.apiKeyHelper.enable {
        # API Key Helper: symlink the wrapper binary to scriptPath so
        # settings.json can reference it at its stable home-relative location.
        # The wrapper has python314+keyring+bws in its closure via runtimeInputs
        # (not in home.packages) to avoid Python env conflicts in buildEnv.
        "${cfg.apiKeyHelper.scriptPath}" = {
          source = "${apiKeyHelperBin}/bin/claude-api-key-helper";
          executable = true;
        };

        # Template for ~/.config/bws/.env that bws_helper.py reads
        ".config/bws/.env.example" = {
          source = ./bws-env.example;
        };
      };

      packages = [ ];

      # Activation scripts for directory and config setup
      # NOTE: "local" marketplace setup removed - Claude Code doesn't use it by default.
      # See docs/CLAUDE-MARKETPLACE-ARCHITECTURE.md for details.
      activation = {
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
  };
}
