{
  self,
  nixpkgs,
  nixpkgs-unstable,
  llm-agents,
  home-manager,
  ai-llm-prompts,
  jacobpevans-cc-plugins,
  browser-use-skills,
  nix-claude-code,
  nix-codex,
  nix-agy,
  agent-limits-src,
  nix-agent-sandbox-src,
  nix-claude-code-launcher-src,
  nix-codex-launcher-src,
  karpathy-skills,
  mattpocock-skills,
  fabric-src,
  dashmotion,
  ponytail,
  claude-channel-slack,
  last30days-skill,
  autoresearch,
  context-engineering-kit,
  managing-dependencies,
  langfuse-skills,
  awesome-claude-skills,
  vct-cribl-cli,
  vct-splunk-cli,
  gh-stack,
  herdr-remote-src,
  herdr-hail-src,
  token-meter-src,
  homelab-contracts,
  ...
}:
let
  supportedSystems = [
    "aarch64-darwin"
    "x86_64-linux"
  ];
  forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  homebrewNix = import ../lib/homebrew.nix;
  # In `let`, not just the outputs attrset, so `checks` can reference the
  # composed renderAutonomous — attrset siblings are not in scope.
  nixAiLib = import ./lib.nix {
    inherit
      nixpkgs
      nix-claude-code
      nix-codex
      nix-agy
      agent-limits-src
      homebrewNix
      homelab-contracts
      ;
  };
  # The reusable lane checker consumes the model names a routed Home Manager
  # configuration actually gives each harness, not host-specific values.
  laneAliasParityNames =
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      fixtures = import ../lib/checks-fixtures.nix {
        inherit home-manager pkgs;
        aiModule = self.homeManagerModules.default;
      };
      cfg = fixtures.hmConfigRouter.config.programs;
      aiStack = import ../vars/ai-stack.nix;
      sortedUnique = values: nixpkgs.lib.unique (builtins.sort builtins.lessThan values);
      claudeRouterNames = (pkgs.callPackage ../modules/claude-router-pkgs.nix { }).routerNames;
      cecliNames = map (name: nixpkgs.lib.removePrefix "openai/" name) [
        cfg.cecli.model
        cfg.cecli.weakModel
        cfg.cecli.editorModel
      ];
      names =
        cfg.litellmLocal.aliases
        ++ cfg.opencode.litellmRoles
        ++ cfg.opencode.routerGoAliases
        ++ cfg.codex.litellmProfileNames
        ++ claudeRouterNames
        ++ [ cfg.qwen-code.model ]
        ++ cecliNames
        ++ [
          cfg.fabric.defaultModel
          aiStack.router.model
        ];
      # These settings call provider APIs directly. Keep them out of `names`,
      # which the shared checker treats as router names. The current checker
      # ignores this key; a contracts follow-up can report these exceptions.
      directProviderExemptions = {
        antigravity_cli = sortedUnique (
          nixpkgs.lib.optional (cfg.antigravity-cli.defaultModel != null) cfg.antigravity-cli.defaultModel
        );
        claude_zai = sortedUnique [
          aiStack.zai.claude.primaryModel
          aiStack.zai.claude.fastModel
        ];
        codex_zai = [ aiStack.zai.codex.model ];
        zcode = [ aiStack.zai.zcode.model ];
      };
    in
    {
      source = "nix-ai";
      names = sortedUnique names;
      direct_provider_exemptions = directProviderExemptions;
    };
in
{
  homeManagerModules = import ./home-manager-modules.nix {
    inherit (nixpkgs) lib;
    inherit self;
    inherit
      ai-llm-prompts
      jacobpevans-cc-plugins
      browser-use-skills
      nix-claude-code
      nix-codex
      nix-agy
      nix-claude-code-launcher-src
      nix-codex-launcher-src
      karpathy-skills
      mattpocock-skills
      nixpkgs-unstable
      llm-agents
      herdr-hail-src
      dashmotion
      ponytail
      claude-channel-slack
      last30days-skill
      autoresearch
      context-engineering-kit
      managing-dependencies
      langfuse-skills
      awesome-claude-skills
      vct-cribl-cli
      vct-splunk-cli
      gh-stack
      token-meter-src
      homelab-contracts
      nix-agent-sandbox-src
      ;
    inherit (nixAiLib) agentNofile;
  };

  # CI-friendly and cross-flake outputs. Extracted to flake/lib.nix to keep
  # this file under the file-size budget while preserving the explanatory
  # comments — see that file. The public `nix-ai.lib.*` API is additive.
  lib = nixAiLib // {
    inherit laneAliasParityNames;
  };

  # System-level modules. herdr is the first thing this flake manages that
  # runs as a service on a Linux guest rather than a launchd agent on the
  # Mac, so this output is new — see flake/nixos-modules.nix.
  nixosModules = import ./nixos-modules.nix {
    inherit llm-agents herdr-remote-src herdr-hail-src;
  };

  # Whole-guest configurations. `nixosModules` above are importable but not
  # deployable; ansible-proxmox-ai's nixos_deploy role dereferences
  # `nixosConfigurations.<host>`, which is what this provides. x86_64-linux
  # only — see flake/nixos-configurations.nix.
  nixosConfigurations = import ./nixos-configurations.nix {
    inherit nixpkgs llm-agents;
    inherit (self) nixosModules;
  };

  # Extracted to flake/checks.nix to stay under the 12KB file-size gate.
  # Still x86_64-linux-scoped; see that file for why.
  checks = import ./checks.nix {
    inherit
      self
      nixpkgs
      home-manager
      nixAiLib
      ai-llm-prompts
      herdr-remote-src
      homelab-contracts
      ;
    src = ../.;
  };

  # Extracted to flake/packages.nix to stay under the 12KB file-size gate.
  packages = import ./packages.nix {
    inherit
      nixpkgs
      forAllSystems
      fabric-src
      vct-cribl-cli
      vct-splunk-cli
      ;
    inherit (self) nixosConfigurations;
    inherit herdr-remote-src herdr-hail-src;
  };

  devShells = import ./dev-shells.nix { inherit nixpkgs forAllSystems ai-llm-prompts; };

  # Extracted to flake/overlays.nix to stay under the 12KB file-size gate.
  overlays = import ./overlays.nix { inherit self; };

  # Formatter
  formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
}
