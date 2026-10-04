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
    # Cursor CLI remains sourced from unstable because the release branch is stale.
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

    # Launcher source from the current API branch; the module flake above
    # remains pinned to its release branch.
    nix-claude-code-launcher-src = {
      url = "github:dryvist/nix-claude-code/develop";
      flake = false;
    };

    # The Codex module is still pinned to its release branch.
    nix-codex = {
      url = "github:dryvist/nix-codex/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-codex-launcher-src = {
      url = "github:dryvist/nix-codex/develop";
      flake = false;
    };

    # Pure resource-limit value, without evaluating the system flake's inputs.
    agent-limits-src = {
      url = "github:dryvist/nix-darwin/develop";
      flake = false;
    };

    # ZCode dispatcher client module and package source. Source-only avoids a
    # cycle because nix-agent-sandbox consumes nix-ai for container configs.
    nix-agent-sandbox-src = {
      url = "github:dryvist/nix-agent-sandbox/43f8141613de6b15e8b69f264a45ebec2f92773e";
      flake = false;
    };

    nix-agy = {
      url = "github:dryvist/nix-agy/develop";
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

  outputs = inputs: import ./flake/outputs.nix inputs;
}
