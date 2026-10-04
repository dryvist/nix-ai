{
  self,
  nixpkgs,
  nixpkgs-unstable,
  llm-agents,
  home-manager,
  ai-llm-prompts,
  ai-assistant-instructions,
  jacobpevans-cc-plugins,
  browser-use-skills,
  nix-claude-code,
  nix-codex,
  nix-agy,
  agent-limits-src,
  nix-claude-code-launcher-src,
  nix-codex-launcher-src,
  karpathy-skills,
  mattpocock-skills,
  fabric-src,
  dashmotion,
  ponytail,
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
in
{
  homeManagerModules = import ./home-manager-modules.nix {
    inherit (nixpkgs) lib;
    inherit
      ai-assistant-instructions
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
      dashmotion
      ponytail
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
      ;
    inherit (nixAiLib) agentNofile;
  };

  # CI-friendly and cross-flake outputs. Extracted to flake/lib.nix to keep
  # this file under the file-size budget while preserving the explanatory
  # comments — see that file. The public `nix-ai.lib.*` shape is unchanged.
  lib = nixAiLib;

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
