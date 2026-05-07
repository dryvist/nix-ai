{
  description = "AI CLI ecosystem for Claude, Gemini, Copilot, and Codex (Nix flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Official Anthropic repositories
    claude-code-plugins = {
      url = "github:anthropics/claude-code";
      flake = false;
    };

    claude-cookbooks = {
      url = "github:anthropics/claude-cookbooks";
      flake = false;
    };

    # AI Assistant Instructions - source of truth for AI agent configuration
    ai-assistant-instructions = {
      url = "github:JacobPEvans/ai-assistant-instructions";
      flake = false;
    };

    # Marketplace Inputs
    anthropic-agent-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
    bills-claude-skills = {
      url = "github:BillChirico/bills-claude-skills";
      flake = false;
    };
    bitwarden-marketplace = {
      url = "github:bitwarden/ai-plugins";
      flake = false;
    };
    cc-dev-tools = {
      url = "github:Lucklyric/cc-dev-tools";
      flake = false;
    };
    cc-marketplace = {
      url = "github:ananddtyagi/cc-marketplace";
      flake = false;
    };
    claude-code-plugins-plus = {
      url = "github:jeremylongshore/claude-code-plugins-plus";
      flake = false;
    };
    claude-code-workflows = {
      url = "github:wshobson/agents";
      flake = false;
    };
    claude-plugins-official = {
      url = "github:anthropics/claude-plugins-official";
      flake = false;
    };
    claude-skills = {
      url = "github:secondsky/claude-skills";
      flake = false;
    };
    jacobpevans-cc-plugins = {
      url = "github:JacobPEvans/claude-code-plugins";
      flake = false;
    };
    lunar-claude = {
      url = "github:basher83/lunar-claude";
      flake = false;
    };
    obsidian-skills = {
      url = "github:kepano/obsidian-skills";
      flake = false;
    };
    openai-codex = {
      url = "github:openai/codex-plugin-cc";
      flake = false;
    };
    axton-obsidian-visual-skills = {
      url = "github:axtonliu/axton-obsidian-visual-skills";
      flake = false;
    };
    superpowers-marketplace = {
      url = "github:obra/superpowers-marketplace";
      flake = false;
    };
    visual-explainer-marketplace = {
      url = "github:nicobailon/visual-explainer";
      flake = false;
    };
    wakatime = {
      url = "github:wakatime/claude-code-wakatime";
      flake = false;
    };

    # Hugging Face Skills marketplace - hf-cli, datasets, papers, models, gradio, etc.
    huggingface-skills = {
      url = "github:huggingface/skills";
      flake = false;
    };

    # Skill-only repos (no marketplace structure — wrapped via synthetic derivation)
    browser-use-skills = {
      url = "github:browser-use/browser-use";
      flake = false;
    };
    vct-cribl-pack-validator-skills = {
      url = "github:VisiCore/vct-cribl-pack-validator";
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
      url = "github:danielmiessler/fabric/v1.4.444";
      flake = false;
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      claude-code-plugins,
      claude-cookbooks,
      ai-assistant-instructions,
      anthropic-agent-skills,
      bills-claude-skills,
      bitwarden-marketplace,
      cc-dev-tools,
      cc-marketplace,
      claude-code-plugins-plus,
      claude-code-workflows,
      claude-plugins-official,
      claude-skills,
      jacobpevans-cc-plugins,
      lunar-claude,
      obsidian-skills,
      openai-codex,
      axton-obsidian-visual-skills,
      superpowers-marketplace,
      visual-explainer-marketplace,
      wakatime,
      huggingface-skills,
      browser-use-skills,
      vct-cribl-pack-validator-skills,
      pal-mcp-server,
      fabric-src,
      ...
    }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      marketplaceInputs = {
        inherit
          anthropic-agent-skills
          bills-claude-skills
          bitwarden-marketplace
          browser-use-skills
          huggingface-skills
          vct-cribl-pack-validator-skills
          cc-dev-tools
          cc-marketplace
          claude-code-plugins-plus
          claude-code-workflows
          claude-plugins-official
          claude-skills
          jacobpevans-cc-plugins
          lunar-claude
          obsidian-skills
          openai-codex
          axton-obsidian-visual-skills
          superpowers-marketplace
          visual-explainer-marketplace
          wakatime
          ;
      };
    in
    {
      homeManagerModules = import ./flake/home-manager-modules.nix {
        inherit
          ai-assistant-instructions
          marketplaceInputs
          claude-code-plugins
          claude-cookbooks
          pal-mcp-server
          fabric-src
          ;
      };

      # CI-friendly outputs
      lib = {
        ci = {
          claudeSettingsJson =
            let
              aiCommon = import ./modules/common {
                inherit ai-assistant-instructions;
                inherit (nixpkgs) lib;
                config = {
                  home.homeDirectory = "/home/user";
                };
              };
              inherit (aiCommon) permissions formatters;
            in
            builtins.toJSON (
              import ./lib/claude-settings.nix {
                inherit (nixpkgs) lib;
                homeDir = "/home/user";
                schemaUrl = "https://json.schemastore.org/claude-code-settings.json";
                permissions = {
                  allow = formatters.claude.formatAllowed permissions;
                  deny = formatters.claude.formatDenied permissions;
                  ask = [ ];
                };
                plugins =
                  (import ./modules/claude-plugins.nix {
                    inherit (nixpkgs) lib;
                    inherit marketplaceInputs claude-cookbooks;
                  }).pluginConfig;
                additionalDirectories = [ "~/.claude/" ]; # CI fixture — real list in modules/claude-config.nix
              }
            );
          codexRules =
            let
              aiCommon = import ./modules/common {
                inherit ai-assistant-instructions;
                inherit (nixpkgs) lib;
                config = {
                  home.homeDirectory = "/home/user";
                };
              };
              inherit (aiCommon) permissions formatters;
            in
            formatters.codex.formatRulesFile permissions;
        };

        # Expose lib functions
        claude-settings = import ./lib/claude-settings.nix;
        claude-registry = import ./lib/claude-registry.nix;
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

        # Shared permission + formatter engine. Exposed for cross-flake consumers
        # (e.g., nix-ai-claude) so the source of truth for tool-agnostic command
        # permissions stays in this flake. Callers pass { lib, config,
        # ai-assistant-instructions, excludeDenyFiles?, excludeDenyCommands? }
        # and receive { permissions, formatters } — see modules/common/default.nix.
        aiCommon = import ./modules/common;
      };

      # Quality checks (formatting, linting, dead code, shellcheck, module-eval)
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./lib/checks.nix {
          inherit
            pkgs
            home-manager
            pal-mcp-server
            fabric-src
            ;
          src = ./.;
          aiModule = self.homeManagerModules.default;
        }
      );

      # Expose custom packages for nix-update automation
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          gh-aw = pkgs.callPackage ./modules/gh-extensions/gh-aw.nix { };
          pal-mcp-server = pkgs.callPackage ./modules/mcp/pal-package.nix { inherit pal-mcp-server; };
          fabric-ai = pkgs.callPackage ./modules/fabric/package.nix { inherit fabric-src; };
          cecli = pkgs.callPackage ./modules/cecli/package.nix { };
        }
      );

      # Default overlay — injects every flake-exported package into pkgs.
      # Consumers register this via:
      #   nixpkgs.overlays = [ nix-ai.overlays.default ];
      # Required when importing this flake's homeManagerModules, since those
      # modules reference pkgs.<name> (e.g. modules/cecli/packages.nix uses
      # pkgs.cecli). Any package added to `packages` above is automatically
      # available — consumers do not need to enumerate package names.
      # The `prev ? system` guard makes the overlay safe to call with the
      # empty attrsets the flake schema validator uses (`overlay {} {}`).
      overlays.default = _final: prev: if prev ? system then self.packages.${prev.system} or { } else { };

      # Formatter
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
