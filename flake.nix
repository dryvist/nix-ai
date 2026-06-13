{
  description = "AI CLI ecosystem for Claude, Gemini, Copilot, and Codex (Nix flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Second nixpkgs only for llama-swap: 25.11-darwin froze it at v165 on
    # 2025-09-22 with no backports. See nix-ai#801.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Official Anthropic plugin marketplace source (also re-exposed via
    # nix-claude-code). Kept here because nix-ai modules still reference it
    # directly for cookbook command/agent discovery.
    claude-code-plugins = {
      url = "github:anthropics/claude-code";
      flake = false;
    };

    # AI Assistant Instructions - source of truth for AI agent configuration.
    ai-assistant-instructions = {
      url = "github:JacobPEvans/ai-assistant-instructions";
      flake = false;
    };

    # Declarative Claude Code module. Owns programs.claude.* schema,
    # marketplace catalog, synthetic marketplace derivations, lib helpers,
    # and the byte-equivalence CI fixture. The 20 marketplace inputs that
    # previously lived in nix-ai are now transitive inputs of this flake.
    nix-claude-code = {
      url = "github:dryvist/nix-claude-code";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        ai-assistant-instructions.follows = "ai-assistant-instructions";
        claude-code-plugins.follows = "claude-code-plugins";
      };
    };

    # Behavioral/workflow skills from Andrej Karpathy. Lives here (not in
    # nix-claude-code) because it's a nix-ai-specific addition that landed
    # on main after PR3 started; promote upstream when convenient.
    karpathy-skills = {
      url = "github:forrestchang/andrej-karpathy-skills";
      flake = false;
    };

    # PAL MCP server - pinned for supply-chain safety; auto-bumped by deps-update-flake.yml
    pal-mcp-server = {
      url = "github:BeehiveInnovations/pal-mcp-server";
      flake = false;
    };

    # Fabric - Daniel Miessler's 252+ AI prompt pattern framework (Go CLI).
    # Source of both the fabric binary and the pattern library. The flake input
    # tag and lib/versions.nix.fabric must stay in sync — Renovate opens separate
    # PRs for each (nix manager for this URL, custom.regex for the version).
    # scripts/check-fabric-version-sync.sh catches label drift; vendorHash
    # catches source changes that weren't accompanied by a version bump.
    fabric-src = {
      url = "github:danielmiessler/fabric/v1.4.452";
      flake = false;
    };

    # DashMotion - animated technical diagram skill (flowcharts + architecture
    # diagrams as self-contained HTML+SVG files using stroke-dashoffset +
    # animateMotion; no external dependencies).
    dashmotion = {
      url = "github:csthink/dashmotion";
      flake = false;
    };

    # Ponytail - "lazy senior dev mode" behavioral skill (YAGNI, stdlib-first,
    # no unrequested abstractions). Dual-channel: a flat skills/<name>/SKILL.md
    # layout (consumed cross-tool by agent-skills) AND a native .claude-plugin/
    # marketplace (consumed by Claude). Wired like karpathy-skills.
    ponytail = {
      url = "github:DietrichGebert/ponytail";
      flake = false;
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ai-assistant-instructions,
      nix-claude-code,
      karpathy-skills,
      pal-mcp-server,
      fabric-src,
      dashmotion,
      ponytail,
      ...
    }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      homebrewNix = import ./lib/homebrew.nix;
    in
    {
      homeManagerModules = import ./flake/home-manager-modules.nix {
        inherit
          ai-assistant-instructions
          nix-claude-code
          karpathy-skills
          pal-mcp-server
          nixpkgs-unstable
          dashmotion
          ponytail
          ;
      };

      # CI-friendly outputs
      lib = {
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
              aiCommon = import ./modules/common {
                inherit nix-claude-code lib;
                config = {
                  home.homeDirectory = "/home/user";
                };
              };
              inherit (aiCommon) permissions formatters;
              pluginTiers = import ./modules/claude/plugins {
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
              aiCommon = import ./modules/common {
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
        versions = import ./lib/versions.nix;

        # Role-name → physical mlx-community/* model ID registry.
        # Exported as a plain attrset so foreign consumers (e.g.
        # orbstack-kubernetes Bifrost config) can consume it without
        # importing the home-manager module system. The module at
        # modules/ai-stack/default.nix uses this same file as its option
        # default — one source of truth.
        aiStackModels = import ./lib/ai-stack-models.nix;

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
        aiCommon = import ./modules/common;
      };

      # Quality checks (formatting, linting, dead code, shellcheck, module-eval).
      #
      # Scoped to x86_64-linux only so `nix flake check --all-systems` succeeds
      # from a single linux runner. All checks in lib/checks.nix are source-only
      # or evaluation-wrapped — running once on the CI system is sufficient.
      # Cross-platform breakage is still caught by `--all-systems` evaluating
      # `packages.<system>`, `formatter.<system>`, and `overlays.default` on
      # every declared system.
      checks =
        let
          system = "x86_64-linux";
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          ${system} = import ./lib/checks.nix {
            inherit
              pkgs
              home-manager
              pal-mcp-server
              ;
            src = ./.;
            aiModule = self.homeManagerModules.default;
          };
        };

      # Expose custom packages for nix-update automation
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cecliPkg = pkgs.callPackage ./modules/cecli/package.nix { };
        in
        {
          gh-aw = pkgs.callPackage ./modules/gh-extensions/gh-aw.nix { };
          pal-mcp-server = pkgs.callPackage ./modules/mcp/pal-package.nix { inherit pal-mcp-server; };
          fabric-ai = pkgs.callPackage ./modules/fabric/package.nix { inherit fabric-src; };
          cecli = cecliPkg;
          inherit (cecliPkg.passthru) mcp;
        }
      );

      # Default overlay — injects every flake-exported package into pkgs.
      # Consumers register this via:
      #   nixpkgs.overlays = [ nix-ai.overlays.default ];
      # Required when importing this flake's homeManagerModules, since those
      # modules reference pkgs.<name> (e.g. modules/cecli/packages.nix uses
      # pkgs.cecli). Any package added to `packages` above is automatically
      # available — consumers do not need to enumerate package names.
      #
      # Use prev.stdenv.hostPlatform.system (not prev.system). The bare
      # `system` attribute is a deprecated alias in nixpkgs whose
      # warnAlias machinery triggers infinite recursion when evaluated
      # inside an overlay during home-manager's _module.args.pkgs path.
      # The stdenv check guards against the empty attrsets the
      # flake schema validator passes (`overlay {} {}`).
      overlays.default =
        _final: prev:
        if prev ? stdenv then self.packages.${prev.stdenv.hostPlatform.system} or { } else { };

      # Formatter
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
