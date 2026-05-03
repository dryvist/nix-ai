# nix-ai Root Home-Manager Module
#
# Aggregates all AI CLI configuration into a single home-manager module.
# Consumed by nix-darwin (or any home-manager setup) via:
#   nix-ai.homeManagerModules.default
#
# Module arguments injected via _module.args from flake.nix (see homeManagerModules)

{
  config,
  pkgs,
  lib,
  ai-assistant-instructions,
  marketplaceInputs,
  claude-cookbooks,
  claude-code-plugins,
  fabric-src,
  userConfig ? {
    ai.claudeSchemaUrl = "https://json.schemastore.org/claude-code-settings.json";
  },
  ...
}:

let
  # Claude Code configuration values
  claudeConfig = import ./claude-config.nix {
    inherit
      config
      pkgs
      lib
      ai-assistant-instructions
      marketplaceInputs
      claude-cookbooks
      fabric-src
      ;
  };

  # AgentsMD symlinks from ai-assistant-instructions flake input
  agentsMdSymlinks = {
    "CLAUDE.md" = {
      source = "${ai-assistant-instructions}/CLAUDE.md";
      force = true;
    };
    "AGENTS.md" = {
      source = "${ai-assistant-instructions}/AGENTS.md";
      force = true;
    };
    "agentsmd" = {
      source = "${ai-assistant-instructions}/agentsmd";
      force = true;
    };
  };

  # Copilot CLI configuration
  copilotFiles = import ./copilot.nix {
    inherit
      config
      lib
      pkgs
      ai-assistant-instructions
      ;
  };

  # GitHub CLI extensions
  ghExtensions = import ./gh-extensions {
    inherit pkgs lib;
    inherit (pkgs) fetchFromGitHub;
  };
in
{
  imports = [
    ./ai-shell.nix
    ./ai-stack
    ./agent-skills
    ./claude
    ./claude-latest.nix
    ./codex
    ./gemini
    ./fabric
    ./maestro
    ./mcp
    ./mcp/module.nix
    ./mlx
    ./open-webui.nix
    ./routines
  ];

  config = {
    home = {
      # AI development tools (MCP servers, linters, CLI wrappers)
      inherit (import ./ai-tools.nix { inherit pkgs; }) packages;

      file = copilotFiles // agentsMdSymlinks;

      activation = {
        # Claude Code Settings Validation (post-rebuild)
        validateClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ${./scripts/validate-claude-settings.sh} \
            "${config.home.homeDirectory}/.claude/settings.json" \
            "${userConfig.ai.claudeSchemaUrl}"
        '';

        cleanupLegacyGeminiMd = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          gemini_md="${config.home.homeDirectory}/GEMINI.md"
          if [ -L "$gemini_md" ]; then
            target=$(readlink "$gemini_md")
            case "$target" in
              /nix/store/*)
                $DRY_RUN_CMD rm "$gemini_md"
                ;;
            esac
          fi
        '';

        # open-webui: installed via uv (nixpkgs broken on darwin — see modules/open-webui.nix)
        installOpenWebui = lib.hm.dag.entryAfter [ "writeBoundary" "knownMarketplacesMerge" ] ''
          if ! ${lib.getExe pkgs.uv} tool list 2>/dev/null | grep -q "^open-webui"; then
            echo "-> Installing open-webui via uv (Python 3.14)..."
            $DRY_RUN_CMD ${lib.getExe pkgs.uv} tool install "open-webui==0.9.2" --python 3.14
          fi
        '';

        # browser-use: CLI for browser automation (not in nixpkgs)
        installBrowserUse = lib.hm.dag.entryAfter [ "writeBoundary" "knownMarketplacesMerge" ] ''
          if ! ${lib.getExe pkgs.uv} tool list 2>/dev/null | grep -q "^browser-use"; then
            echo "-> Installing browser-use via uv..."
            $DRY_RUN_CMD ${lib.getExe pkgs.uv} tool install "browser-use==0.12.6"
          fi
        '';
      };
    };

    # Programs configuration
    programs = {
      # Claude Code declarative configuration
      claude = claudeConfig;

      # Claude Code statusline — ccstatusline active; others dormant for rollback
      claudeStatusline.enable = false;
      claudeStatuslineDaniel3303.enable = false;
      claudeStatuslineCcstatusline.enable = true;

      # OpenAI Codex configuration (settings handled by modules/codex/)
      codex = {
        enable = true;
      };

      # Gemini CLI configuration (settings handled by modules/gemini/)
      gemini = {
        enable = true;
        worktrees = true;
        defaultApprovalMode = "auto_edit";
      };

      # Shared skill deployment for Codex/Gemini compatibility layers.
      agentSkills.enable = true;

      # MLX inference server (vllm-mlx on port 11434)
      mlx = {
        enable = true;
        # Some local consumers omit max_tokens. Cap the server fallback so
        # uncapped runs cannot expand to vllm-mlx's 32768-token default.
        maxTokens = 8192;
      };

      # Fabric — 252+ AI prompt patterns + CLI (defaults to MLX backend)
      # REST API server is opt-in via programs.fabric.enableServer
      fabric.enable = true;

      # Bleeding-edge Claude Code at ~/.local/bin/claude via the official installer.
      # Coexists with Homebrew's stable `claude`. See modules/ai-aliases.zsh for
      # alias definitions (claude-latest, claude-d, claude-latest-d).
      claude-latest.enable = true;

      # GitHub CLI extension for AI workflows
      gh.extensions = [ ghExtensions.gh-aw ];

      # Scheduled AI routines via launchd
      routines = {
        enable = true;
        tasks.permission-sync = {
          prompt = builtins.readFile ./routines/prompts/permission-sync.md;
          aiTool = "gemini";
          schedule.times = [
            {
              hour = 6;
              minute = 13;
            }
          ];
          workingDirectory = config.home.homeDirectory;
          enabled = true;
        };
      };
    };
  };
}
