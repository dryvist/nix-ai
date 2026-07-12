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
        # nix-claude-code injects fabric-src as the module arg that our
        # fabric-ai package consumes in the composed home config. Pin it to
        # our own fabric-src so the built source matches lib/versions.nix
        # (and the vendorHash); otherwise nix-claude-code's independently
        # pinned fabric-src drifts and the fabric-ai build fails.
        fabric-src.follows = "fabric-src";
      };
    };

    # Behavioral/workflow skills from Andrej Karpathy. Lives here (not in
    # nix-claude-code) because it's a nix-ai-specific addition that landed
    # on main after PR3 started; promote upstream when convenient.
    karpathy-skills = {
      url = "github:forrestchang/andrej-karpathy-skills";
      flake = false;
    };

    # Fabric - Daniel Miessler's 252+ AI prompt pattern framework (Go CLI).
    # Source of both the fabric binary and the pattern library. The flake input
    # tag and lib/versions.nix.fabric must stay in sync — Renovate opens separate
    # PRs for each (nix manager for this URL, custom.regex for the version).
    # The fabric-version-sync check (lib/checks/fabric.nix) catches label drift;
    # vendorHash catches source changes that weren't accompanied by a version bump.
    fabric-src = {
      url = "github:danielmiessler/fabric/v1.4.455";
      flake = false;
    };

    # DashMotion - animated technical diagram skill (flowcharts + architecture
    # diagrams as self-contained HTML+SVG files using stroke-dashoffset +
    # animateMotion; no external dependencies). Skill-only cross-tool input:
    # ships skills/<name>/SKILL.md with no .claude-plugin/, so it flows to
    # ~/.agents/skills via agent-skills auto-discovery, not Claude's registry.
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

    # Autoresearch - autonomous goal-directed iteration engine (modify → verify
    # → keep/discard loop) from uditgoenka/autoresearch. Dual-channel like
    # ponytail: native .claude-plugin/ marketplace (14 /autoresearch:* commands
    # + safety hooks for Claude) AND a self-contained .claude/skills/ skill
    # (consumed cross-tool via agent-skills auto-discovery). Its .opencode/
    # command files feed the opencode module directly.
    autoresearch = {
      url = "github:uditgoenka/autoresearch";
      flake = false;
    };

    # Last30Days - multi-source social research skill. Aggregates Reddit, X,
    # YouTube, TikTok, Hacker News, Polymarket, GitHub, and web results ranked
    # by engagement. Flat skills/<name>/SKILL.md layout; skill-only cross-tool
    # input (no .claude-plugin/).
    last30days-skill = {
      url = "github:mvanhorn/last30days-skill";
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
      fabric-src,
      dashmotion,
      ponytail,
      last30days-skill,
      autoresearch,
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
          nixpkgs-unstable
          dashmotion
          ponytail
          last30days-skill
          autoresearch
          ;
      };

      # CI-friendly and cross-flake outputs. Extracted to flake/lib.nix to keep
      # this file under the file-size budget while preserving the explanatory
      # comments — see that file. The public `nix-ai.lib.*` shape is unchanged.
      lib = import ./flake/lib.nix { inherit nixpkgs nix-claude-code homebrewNix; };

      # Quality checks (formatting, linting, dead code, module-eval).
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
          ${system} =
            (import ./lib/checks.nix {
              inherit
                pkgs
                home-manager
                ;
              src = ./.;
              aiModule = self.homeManagerModules.default;
            })
            // {
              # `nix flake check` only *evaluates* packages.<system> (reports
              # "build skipped") — it never compiles them, so a stale fabric
              # vendorHash after a fabric-src bump passes CI unnoticed (this
              # happened twice: #1145, fixed by #1156/#1159). Aliasing the package
              # as a check forces the Go build — and its vendorHash verification —
              # to actually run. Scoped to the CI system (x86_64-linux) like every
              # other check so a single linux runner covers it.
              fabric-ai-build = self.packages.${system}.fabric-ai;
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
