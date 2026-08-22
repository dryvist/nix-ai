{
  description = "AI CLI ecosystem for Claude, Gemini, Copilot, and Codex (Nix flake)";

  inputs = {
    # Both are channel branches = the intended major-version pins. Renovate
    # cannot bump either — a branch ref never changes, so there is nothing to
    # diff. deps-flake-lock.yml relocks weekly, moving both together.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Second nixpkgs only for llama-swap: 25.11-darwin froze it at v165 on
    # 2025-09-22 with no backports. See nix-ai#801.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ai-llm-prompts = {
      url = "github:dryvist/ai-llm-prompts/9f55dee4840752c5b73f92278bc75fbe701e8dff";
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
      # Pinned to main explicitly: nix-claude-code is git-flow (default
      # branch develop), so an unref'd url resolves to develop and tracks
      # unreleased commits instead of release-please-tagged releases.
      url = "github:dryvist/nix-claude-code/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        ai-assistant-instructions.follows = "ai-assistant-instructions";
        claude-code-plugins.follows = "claude-code-plugins";
        jacobpevans-cc-plugins.follows = "jacobpevans-cc-plugins";
        browser-use-skills.follows = "browser-use-skills";
        # nix-claude-code injects fabric-src as the module arg that our
        # fabric-ai package consumes in the composed home config. Pin it to
        # our own fabric-src so the built source matches lib/versions.nix
        # (and the vendorHash); otherwise nix-claude-code's independently
        # pinned fabric-src drifts and the fabric-ai build fails.
        fabric-src.follows = "fabric-src";
      };
    };

    # The other two per-CLI leaves, composed into `lib.renderAutonomous` by
    # flake/lib.nix. Pinned to main for the same git-flow reason as
    # nix-claude-code; `follows` only keeps the lock lean.
    nix-codex = {
      url = "github:dryvist/nix-codex/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-agy = {
      url = "github:dryvist/nix-agy/main";
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

    # ---- Third-party skill inputs -------------------------------------
    # modules/agent-skills walks each for every known SKILL.md layout and
    # deploys to ~/.agents/skills. One that also ships .claude-plugin/ is
    # "dual-channel": register it in modules/claude/marketplaces.nix and enable
    # its plugin in a tier file to reach Claude, which does not read
    # ~/.agents/skills. Licenses noted only where they constrain us — consuming
    # from the store is fine, copying into a repo we publish is not.

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

    # Only `file-organizer` is taken; its <repo>/<skill>/SKILL.md layout
    # matches no discovery pattern, so it is wired by path through
    # programs.agentSkills.local. Unlicensed upstream — never copied.
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

  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ai-llm-prompts,
      ai-assistant-instructions,
      jacobpevans-cc-plugins,
      browser-use-skills,
      nix-claude-code,
      nix-codex,
      nix-agy,
      karpathy-skills,
      fabric-src,
      dashmotion,
      ponytail,
      last30days-skill,
      autoresearch,
      context-engineering-kit,
      managing-dependencies,
      awesome-claude-skills,
      vct-cribl-cli,
      vct-splunk-cli,
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
          homebrewNix
          ;
      };
      orchestratorPromptNames = [
        "nix-ai-code-explain-example"
        "nix-ai-code-review-analysis-example"
        "nix-ai-code-review-categorization-example"
        "nix-ai-code-review-example"
        "nix-ai-default-system"
        "nix-ai-structured-extract-example"
        "nix-ai-vault-search-example"
      ];
      orchestratorPromptDir =
        system: "${ai-llm-prompts.packages.${system}.applications}/share/ai-llm-prompts/applications";
      # Built for EVERY supported system, deliberately.
      #
      # These were scoped to x86_64-linux alone so one linux runner could serve
      # `--all-systems`. The cost was invisible: `nix flake check` on an
      # aarch64-darwin workstation found no `checks.aarch64-darwin` and exited 0
      # having evaluated nothing, so every assertion below passed VACUOUSLY on
      # the machine where the config is actually developed. Two catalog defects
      # shipped to develop behind that false negative (2026-08-14), and the
      # openrouter/splunk breakage this commit fixes lived through months of
      # green local checks for the same reason.
      #
      # The assertions are pure evaluation over a home-manager fixture and are
      # not platform-specific, so building them per-system costs an eval and
      # buys local enforcement. Entries that genuinely need a linux builder stay
      # pinned to x86_64-linux below.
      #
      # Note for CI: `--all-systems` from a linux-only runner will now try to
      # realise the darwin markers and fail. Run `nix flake check` per system on
      # a matching runner instead.
      mkChecks =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          linuxOnly = system == "x86_64-linux";
        in
        (import ./lib/checks.nix {
          inherit
            pkgs
            home-manager
            ;
          src = ./.;
          aiModule = self.homeManagerModules.default;
          inherit (nixAiLib) renderAutonomous;
        })
        // {
          orchestrator-prompt-assets =
            assert builtins.all (
              name: builtins.pathExists (ai-llm-prompts + "/applications/${name}.md")
            ) orchestratorPromptNames;
            pkgs.writeText "nix-ai-orchestrator-prompt-assets" ''
              Validated ${toString (builtins.length orchestratorPromptNames)} catalog prompts.
            '';
        }
        // nixpkgs.lib.optionalAttrs linuxOnly {
          # `nix flake check` only *evaluates* packages.<system> (reports
          # "build skipped") — it never compiles them, so a stale fabric
          # vendorHash after a fabric-src bump passes CI unnoticed (this
          # happened twice: #1145, fixed by #1156/#1159). Aliasing the package
          # as a check forces the Go build — and its vendorHash verification —
          # to actually run. Kept on the linux CI system: it is a real
          # compile, not an evaluation, so one runner covering it is enough.
          fabric-ai-build = self.packages.${system}.fabric-ai;
        };
    in
    {
      homeManagerModules = import ./flake/home-manager-modules.nix {
        inherit
          ai-assistant-instructions
          jacobpevans-cc-plugins
          browser-use-skills
          nix-claude-code
          karpathy-skills
          nixpkgs-unstable
          dashmotion
          ponytail
          last30days-skill
          autoresearch
          context-engineering-kit
          managing-dependencies
          awesome-claude-skills
          vct-cribl-cli
          vct-splunk-cli
          ;
      };

      # CI-friendly and cross-flake outputs. Extracted to flake/lib.nix to keep
      # this file under the file-size budget while preserving the explanatory
      # comments — see that file. The public `nix-ai.lib.*` shape is unchanged.
      lib = nixAiLib;

      checks = forAllSystems mkChecks;

      # Extracted to flake/packages.nix to stay under the 12KB file-size gate.
      packages = import ./flake/packages.nix {
        inherit
          nixpkgs
          forAllSystems
          fabric-src
          vct-cribl-cli
          vct-splunk-cli
          ;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.uv ];
            NIX_AI_PROMPT_DIR = orchestratorPromptDir system;
          };
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
