# CI-friendly and cross-flake `lib` outputs for nix-ai.
#
# Extracted from flake.nix to keep that file under the repo file-size budget
# (.file-size.yml: warn 6 KB / error 12 KB) without dropping the explanatory
# comments. Same split pattern as flake/home-manager-modules.nix — the flake
# wires this in as `lib = import ./flake/lib.nix { ... }`, so the public
# `nix-ai.lib.*` attribute set is byte-for-byte unchanged.
{
  nixpkgs,
  nix-claude-code,
  homebrewNix,
}:
{
  ci = {
    # Render the same settings.json shape nix-ai's pre-PR3 fixture
    # produced (top-level $schema, alwaysThinkingEnabled,
    # enabledPlugins, extraKnownMarketplaces, permissions{allow,
    # ask,deny,additionalDirectories,defaultMode}, statusLine).
    # Built from nix-claude-code.lib helpers so the marketplace
    # catalog and permission shape stay in one repo.
    claudeSettingsJson =
      let
        inherit (nixpkgs) lib;
        ncc = nix-claude-code.lib;
        aiCommon = import ../modules/common {
          inherit nix-claude-code lib;
          config = {
            home.homeDirectory = "/home/user";
          };
        };
        inherit (aiCommon) permissions formatters;
        pluginTiers = import ../modules/claude/plugins {
          inherit lib;
          marketplaceInputs = nix-claude-code.inputs;
        };
        # nix-claude-code's catalog lacks jacobpevans-cc-plugins
        # (PR2 oversight) and karpathy-skills (added on main after
        # PR3 started). Splice them in to keep nix-ai's CI output
        # in lockstep with pre-PR3 behavior.
        augmentedCatalog = ncc.marketplaceCatalog.marketplaces // {
          "jacobpevans-cc-plugins" = {
            source = {
              type = "github";
              url = "JacobPEvans/claude-code-plugins";
            };
          };
          "karpathy-skills" = {
            source = {
              type = "github";
              url = "forrestchang/andrej-karpathy-skills";
            };
          };
          "ponytail" = {
            source = {
              type = "github";
              url = "DietrichGebert/ponytail";
            };
          };
        };
        extraKnownMarketplaces = lib.mapAttrs ncc.claudeRegistry.toClaudeMarketplaceFormat augmentedCatalog;
      in
      builtins.toJSON {
        "$schema" = "https://json.schemastore.org/claude-code-settings.json";
        alwaysThinkingEnabled = true;
        inherit (pluginTiers) enabledPlugins;
        inherit extraKnownMarketplaces;
        permissions = {
          allow = formatters.claude.formatAllowed permissions;
          deny = formatters.claude.formatDenied permissions;
          ask = [ ];
          additionalDirectories = [ "~/.claude/" ];
          defaultMode = "auto";
        };
        statusLine = {
          type = "command";
          command = "/home/user/.claude/statusline-command.sh";
        };
      };

    codexRules =
      let
        aiCommon = import ../modules/common {
          inherit nix-claude-code;
          inherit (nixpkgs) lib;
          config = {
            home.homeDirectory = "/home/user";
          };
        };
        inherit (aiCommon) permissions formatters;
      in
      formatters.codex.formatRulesFile permissions;
  };

  # Versions registry (Renovate-managed pin source-of-truth)
  versions = import ../lib/versions.nix;

  # Named project-scoped plugin packs (api, terraform, proxmox, obsidian, …).
  # Pure attrset so foreign consumers can read the groupings without the module
  # system. The home module (modules/claude/skill-packs.nix) renders these to
  # ~/.config/ai-packs/<name>.json for the `ai-pack` importer. Single source of
  # truth: modules/claude/plugins/packs.nix. See docs/architecture/plugin-scoping.md.
  skillPacks = import ../modules/claude/plugins/packs.nix;

  # Role-name → physical mlx-community/* model ID registry.
  # Exported as a plain attrset so foreign consumers (e.g. the homelab
  # Bifrost gateway config) can consume it without importing the
  # home-manager module system. The module at
  # modules/ai-stack/default.nix uses this same file as its option
  # default — one source of truth.
  aiStackModels = import ../lib/ai-stack-models.nix;

  # Homebrew formula list required by per-agent modules whose
  # preferred install path is brew. nix-darwin reads this from the
  # nix-ai flake input and merges into homebrew.brews. Keeps each
  # agent module self-contained and ready for future graduation
  # to its own flake — see docs/architecture/per-agent-flakes.md.
  brewFormulae = [
    "qwen-code" # programs.qwen-code with installVia = "brew"
  ];

  # AI-tool Homebrew taps and casks. nix-darwin merges these into
  # homebrew.taps and homebrew.casks. Source of truth: lib/homebrew.nix
  # (same file drives the trust.json written by the home-manager module).
  homebrewTaps = homebrewNix.taps;
  homebrewCasks = homebrewNix.casks;

  # Shared permission + formatter engine. Exposed for cross-flake consumers
  # (e.g., nix-ai-claude) so the source of truth for tool-agnostic command
  # permissions stays in this flake. Callers pass { lib, config,
  # nix-claude-code, excludeDenyCategories?, excludeDenyCommands? }
  # and receive { permissions, formatters } — see modules/common/default.nix.
  aiCommon = import ../modules/common;

  # Autonomy profiles (interactive / autonomous / ci) — tool-agnostic
  # deployment postures. See modules/common/profiles.nix for the model.
  profiles = import ../modules/common/profiles.nix { inherit (nixpkgs) lib; };

  # Autonomous-profile config renderers for agent container images
  # (dryvist/nix-agent-sandbox). Pure strings, never written to a host
  # filesystem by any home-manager code path.
  renderAutonomous = import ../modules/common/render-autonomous.nix {
    inherit (nixpkgs) lib;
  };
}
