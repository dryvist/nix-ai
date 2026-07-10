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
  nix-claude-code,
  userConfig ? {
    user.fullName = "JacobPEvans";
  },
  ...
}:

let
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
      nix-claude-code
      ;
  };

  # GitHub CLI extensions
  ghExtensions = import ./gh-extensions {
    inherit pkgs lib;
    inherit (pkgs) fetchFromGitHub;
  };

  versions = import ../lib/versions.nix;
  browserUseVersion = versions.browserUse;

  homebrewCfg = import ../lib/homebrew.nix;

  # ~/.homebrew/trust.json — macOS only. Homebrew 5.2.0/6.0.0 enforces
  # HOMEBREW_REQUIRE_TAP_TRUST; pre-trust the AI-tool taps declared in
  # lib/homebrew.nix so brew bundle keeps working when the default flips.
  # Read-only Nix store symlink is intentional — add new taps in
  # lib/homebrew.nix; never run brew trust directly.
  brewTrustFiles = lib.optionalAttrs pkgs.stdenv.isDarwin {
    ".homebrew/trust.json".text = builtins.toJSON {
      trustedtaps = config.programs.ai-homebrew.trustedTaps;
    };
  };
in
{
  options.programs.ai-homebrew.trustedTaps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = homebrewCfg.taps;
    description = "List of trusted Homebrew taps. Defaults to AI taps but can be extended by other modules.";
  };

  imports = [
    ./maintainer-profile.nix
    ./ai-shell.nix
    ./ai-stack
    ./agent-skills
    ./cecli
    # User-facing claude values (model, marketplaces, hooks, settings.*).
    # The option schema + settings.json renderer comes from
    # `nix-claude-code.homeModules.claude`, imported by
    # `flake/home-manager-modules.nix` (not here, to avoid `imports`
    # depending on `_module.args.nix-claude-code` — infinite recursion).
    ./claude-config.nix
    ./claude/skill-packs.nix
    ./codex
    ./antigravity-ide
    ./antigravity-cli
    ./fabric
    ./maestro
    ./mcp/module.nix
    ./mlx
    ./qwen-code
  ];

  config = {
    home = {
      # AI development tools (MCP servers, linters, CLI wrappers)
      inherit (import ./ai-tools.nix { inherit pkgs; }) packages;

      file = copilotFiles // agentsMdSymlinks // brewTrustFiles;

      activation = {
        # Claude Code Settings Validation (post-rebuild)
        # Schema URL inlined here — same constant nix-claude-code embeds in
        # lib/to-settings-json.nix's "$schema" field, single source of truth
        # is the file produced by nix-claude-code; this validates against it.
        validateClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ${./scripts/validate-claude-settings.sh} \
            "${config.home.homeDirectory}/.claude/settings.json" \
            "https://json.schemastore.org/claude-code-settings.json"
        '';

        cleanupLegacyAntigravityMd = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          antigravity_cli_md="${config.home.homeDirectory}/GEMINI.md"
          if [ -L "$antigravity_cli_md" ]; then
            target=$(readlink "$antigravity_cli_md")
            case "$target" in
              /nix/store/*)
                $DRY_RUN_CMD rm "$antigravity_cli_md"
                ;;
            esac
          fi
        '';

        # browser-use: CLI for browser automation (not in nixpkgs)
        installBrowserUse = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if ! ${lib.getExe pkgs.uv} tool list 2>/dev/null | grep -q "^browser-use"; then
            echo "-> Installing browser-use via uv..."
            $DRY_RUN_CMD ${lib.getExe pkgs.uv} tool install "browser-use==${browserUseVersion}"
          fi
        '';
      };
    };

    # Programs configuration
    programs = {
      # cecli — actively maintained Aider fork (settings handled by modules/cecli/)
      cecli = {
        enable = true;
      };

      # Qwen Code — Alibaba's CLI agent (settings handled by modules/qwen-code/)
      qwen-code = {
        enable = true;
      };

      # OpenAI Codex configuration (settings handled by modules/codex/)
      codex = {
        enable = true;
      };

      # Antigravity IDE configuration (settings handled by modules/antigravity-ide/)
      antigravity-ide = {
        enable = true;
      };

      # Antigravity CLI configuration (settings handled by module./antigravity-cli/)
      antigravity-cli = {
        enable = true;
        worktrees = true;
        defaultApprovalMode = "auto_edit";
      };

      # Shared skill deployment for Codex/Antigravity compatibility layers.
      agentSkills.enable = true;

      # MLX inference server (vllm-mlx on port 11434)
      mlx = {
        enable = true;
        maxTokens = 8192;
      };

      # Fabric — 252+ AI prompt patterns + CLI (defaults to MLX backend)
      fabric.enable = true;

      # Bleeding-edge Claude Code at ~/.local/bin/claude via the upstream
      # opt-in module (nix-claude-code owns programs.claude.latest).
      claude.latest.enable = true;

      # GitHub CLI extension for AI workflows
      gh.extensions = [ ghExtensions.gh-aw ];
    };
  };
}
