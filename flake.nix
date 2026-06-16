{
  description = "AI CLI ecosystem for Claude, Gemini, Copilot, and Codex (Nix flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-plugins = {
      url = "github:anthropics/claude-code";
      flake = false;
    };
    ai-assistant-instructions = {
      url = "github:JacobPEvans/ai-assistant-instructions";
      flake = false;
    };
    nix-claude-code = {
      url = "github:dryvist/nix-claude-code";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        ai-assistant-instructions.follows = "ai-assistant-instructions";
        claude-code-plugins.follows = "claude-code-plugins";
      };
    };
    karpathy-skills = {
      url = "github:forrestchang/andrej-karpathy-skills";
      flake = false;
    };
    pal-mcp-server = {
      url = "github:BeehiveInnovations/pal-mcp-server";
      flake = false;
    };
    fabric-src = {
      url = "github:danielmiessler/fabric/v1.4.452";
      flake = false;
    };
    dashmotion = {
      url = "github:csthink/dashmotion";
      flake = false;
    };
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
      lib = {
        ci = {
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
        versions = import ./lib/versions.nix;
        aiStackModels = import ./lib/ai-stack-models.nix;
        brewFormulae = [
          "qwen-code" # programs.qwen-code with installVia = "brew"
        ];
        homebrewTaps = homebrewNix.taps;
        homebrewCasks = homebrewNix.casks;
        aiCommon = import ./modules/common;
        profiles = import ./modules/common/profiles.nix { inherit (nixpkgs) lib; };
        renderAutonomous = import ./modules/common/render-autonomous.nix {
          inherit (nixpkgs) lib;
        };
      };
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
      overlays.default =
        _final: prev:
        if prev ? stdenv then self.packages.${prev.stdenv.hostPlatform.system} or { } else { };
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
