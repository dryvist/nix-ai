{
  description = "AI CLI ecosystem for Claude, Gemini, Copilot, and Codex";

  # Binary cache for the llm-agents.nix input below. Without it every agent CLI
  # is a from-source build; with it they are all substituted.
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    # Both are channel branches = the intended major-version pins. Renovate
    # cannot bump either — a branch ref never changes, so there is nothing to
    # diff. deps-flake-lock.yml relocks weekly, moving both together.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Second nixpkgs only for llama-swap: 25.11-darwin froze it at v165 on
    # 2025-09-22 with no backports. See nix-ai#801.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Nix packages for AI coding agent CLIs (claude-code, codex, antigravity-cli,
    # copilot-cli, herdr, ...), rebuilt daily by numtide CI for x86_64-linux,
    # aarch64-linux and aarch64-darwin. This is what lets the stack run anywhere
    # but the Mac: the CLIs it supplies used to come from Homebrew casks, which
    # have no Linux path at all.
    #
    # Deliberately does NOT set `inputs.nixpkgs.follows`, unlike every other
    # input here. It pins its own nixpkgs-unstable and cache.numtide.com is keyed
    # to that pin — forcing 26.05 both breaks builds and loses every cache hit.
    llm-agents.url = "github:numtide/llm-agents.nix";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ai-llm-prompts = {
      url = "github:dryvist/ai-llm-prompts";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LLM role map source (lib/role-map.nix).
    homelab-contracts = {
      url = "github:dryvist/homelab-contracts";
      flake = false;
    };

    # Official Anthropic plugin marketplace source (also re-exposed via
    # nix-claude-code). Kept here because nix-ai modules still reference it
    # directly for cookbook command/agent discovery.
    claude-code-plugins = {
      url = "github:anthropics/claude-code";
      flake = false;
    };

    # Token Meter has no flake. Its source is staged and wrapped by the
    # Home Manager module; the weekly lock workflow advances this branch pin.
    token-meter-src = {
      url = "github:dryvist/token-meter/fix/claude-discovery-and-oauth";
      flake = false;
    };

    # herdr-remote's relay (the web/phone dashboard half of herdr). Upstream
    # ships no flake and no nixpkgs entry, so this is a source pin that
    # modules/herdr-remote/package.nix builds. Pinned by REV, never a branch:
    # this is a third-party repo and a branch ref would silently redeploy
    # whatever landed upstream between converges.
    herdr-remote-src = {
      url = "github:dcolinmorgan/herdr-remote/1f5bd32b5121af92c21c9a3b123b10d508f29365";
      flake = false;
    };

    # herdr-hail: the Slack/Discord bridge, an upstream herdr PLUGIN rather
    # than a service of its own. Packaged here so it can run on the herdr
    # guest against the local socket; pinned by rev for the same reason as
    # herdr-remote-src above.
    herdr-hail-src = {
      url = "github:natori-hrj/herdr-hail/9f7120be96cfcc511548eb446ee4ca8b52519b31";
      flake = false;
    };

    # AI Assistant Instructions - source of truth for AI agent configuration.
    ai-assistant-instructions = {
      url = "github:dryvist/ai-assistant-instructions";
      flake = false;
    };

    # Canonical dryvist plugin and cross-tool skill source. Retain the input
    # name for compatibility; non-Claude harnesses consume it directly.
    jacobpevans-cc-plugins = {
      url = "github:dryvist/claude-code-plugins";
      flake = false;
    };

    browser-use-skills = {
      url = "github:browser-use/browser-use";
      flake = false;
    };

    # Declarative Claude Code module and marketplace source.
    nix-claude-code = {
      url = "github:dryvist/nix-claude-code/73d52b7ccf5b359cd45579cd15bcaf65fc773ea1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        ai-assistant-instructions.follows = "ai-assistant-instructions";
        claude-code-plugins.follows = "claude-code-plugins";
        jacobpevans-cc-plugins.follows = "jacobpevans-cc-plugins";
        browser-use-skills.follows = "browser-use-skills";
        # Share the source pin used by fabric-ai and its vendorHash.
        fabric-src.follows = "fabric-src";
      };
    };

    # Per-CLI renderers and launchers; share the existing package set.
    nix-codex = {
      url = "github:dryvist/nix-codex/8c7d623970b50dbf03491fe6cfa0562a86417b55";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pure resource-limit value, without evaluating the system flake's inputs.
    agent-limits-src = {
      url = "github:dryvist/nix-darwin/develop";
      flake = false;
    };
    nix-agy = {
      url = "github:dryvist/nix-agy/76f2d049fc6f535584f14a1b120c5802399b9669";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Behavioral/workflow skills from Andrej Karpathy. Kept here rather than in
    # nix-claude-code; promote upstream when convenient.
    karpathy-skills = {
      url = "github:forrestchang/andrej-karpathy-skills";
      flake = false;
    };

    # Fabric prompt-pattern framework: source of both the binary and the
    # pattern library. This tag and lib/versions.nix.fabric must stay in sync —
    # Renovate opens a separate PR for each, and the fabric-version-sync check
    # (lib/checks/fabric.nix) catches the drift.
    fabric-src = {
      url = "github:danielmiessler/fabric/v1.4.470";
      flake = false;
    };

    # Third-party skills shared with Claude marketplaces.

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    # Animated technical diagrams as self-contained HTML+SVG. Cross-tool only.
    dashmotion = {
      url = "github:csthink/dashmotion";
      flake = false;
    };

    # "Lazy senior dev mode" — YAGNI, stdlib-first, no unrequested
    # abstractions. Dual-channel, wired like karpathy-skills.
    ponytail = {
      url = "github:DietrichGebert/ponytail";
      flake = false;
    };

    # Autonomous goal-directed iteration engine (modify → verify →
    # keep/discard). Dual-channel; its .opencode/ command files also feed the
    # opencode module directly.
    autoresearch = {
      url = "github:uditgoenka/autoresearch";
      flake = false;
    };

    # Multi-source social research, ranked by engagement. Cross-tool only.
    last30days-skill = {
      url = "github:mvanhorn/last30days-skill";
      flake = false;
    };

    # `kaizen` and `why` skills. Dual-channel. GPL-3.0 — never copied.
    context-engineering-kit = {
      url = "github:NeoLabHQ/context-engineering-kit";
      flake = false;
    };

    # Package evaluation and supply-chain hygiene. CC0-1.0. Dual-channel; its
    # marketplace declares a single plugin at ./.
    managing-dependencies = {
      url = "github:andrew/managing-dependencies";
      flake = false;
    };

    langfuse-skills = {
      url = "github:langfuse/skills";
      flake = false;
    };

    awesome-claude-skills = {
      url = "github:ComposioHQ/awesome-claude-skills";
      flake = false;
    };

    vct-cribl-cli = {
      url = "github:VisiCore/vct-cribl-cli/main";
      flake = false;
    };
    vct-splunk-cli = {
      url = "github:VisiCore/vct-splunk-cli/main";
      flake = false;
    };
    gh-stack = {
      url = "github:github/gh-stack";
      flake = false;
    };

  };

  outputs =
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
      homebrewNix = import ./lib/homebrew.nix;
      # In `let`, not just the outputs attrset, so `checks` can reference the
      # composed renderAutonomous — attrset siblings are not in scope.
      nixAiLib = import ./flake/lib.nix {
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
      homeManagerModules = import ./flake/home-manager-modules.nix {
        inherit (nixpkgs) lib;
        inherit
          ai-assistant-instructions
          jacobpevans-cc-plugins
          browser-use-skills
          nix-claude-code
          nix-codex
          nix-agy
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
      nixosModules = import ./flake/nixos-modules.nix {
        inherit llm-agents herdr-remote-src herdr-hail-src;
      };

      # Whole-guest configurations. `nixosModules` above are importable but not
      # deployable; ansible-proxmox-ai's nixos_deploy role dereferences
      # `nixosConfigurations.<host>`, which is what this provides. x86_64-linux
      # only — see flake/nixos-configurations.nix.
      nixosConfigurations = import ./flake/nixos-configurations.nix {
        inherit nixpkgs llm-agents;
        inherit (self) nixosModules;
      };

      # Extracted to flake/checks.nix to stay under the 12KB file-size gate.
      # Still x86_64-linux-scoped; see that file for why.
      checks = import ./flake/checks.nix {
        inherit
          self
          nixpkgs
          home-manager
          nixAiLib
          ai-llm-prompts
          herdr-remote-src
          homelab-contracts
          ;
        src = ./.;
      };

      # Extracted to flake/packages.nix to stay under the 12KB file-size gate.
      packages = import ./flake/packages.nix {
        inherit
          nixpkgs
          forAllSystems
          fabric-src
          vct-cribl-cli
          vct-splunk-cli
          ;
        inherit (self) nixosConfigurations;
        inherit herdr-remote-src herdr-hail-src nixpkgs-unstable;
      };

      devShells = import ./flake/dev-shells.nix { inherit nixpkgs forAllSystems ai-llm-prompts; };

      # Extracted to flake/overlays.nix to stay under the 12KB file-size gate.
      overlays = import ./flake/overlays.nix { inherit self; };

      # Formatter
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
