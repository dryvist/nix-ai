{
  self,
  lib,
  inputs,
  ai-llm-prompts,
  nix-claude-code,
  nix-codex,
  nix-agy,
  nixpkgs-unstable,
  nix-claude-code-launcher-src,
  nix-codex-launcher-src,
  agentNofile,
  llm-agents,
  nix-herdr,
  vct-cribl-cli,
  vct-splunk-cli,
  token-meter-src,
  homelab-contracts,
  nix-agent-sandbox-src,
  herdr-hail-src,
}:
let
  # Skill-source flake inputs, keyed by the name marketplaceInputs exposes.
  # Each value is the flake input it is read from. Only mattpocock differs
  # between the two names.
  skillSourceInputs = {
    jacobpevans-cc-plugins = "jacobpevans-cc-plugins";
    browser-use-skills = "browser-use-skills";
    karpathy-skills = "karpathy-skills";
    mattpocock = "mattpocock-skills";
    orca-skills = "orca-skills";
    modern-web-guidance = "modern-web-guidance";
    dashmotion = "dashmotion";
    vercel-skills = "vercel-skills";
    drawio-skill = "drawio-skill";
    ponytail = "ponytail";
    claude-channel-slack = "claude-channel-slack";
    last30days-skill = "last30days-skill";
    autoresearch = "autoresearch";
    context-engineering-kit = "context-engineering-kit";
    managing-dependencies = "managing-dependencies";
    langfuse-skills = "langfuse-skills";
    gh-stack = "gh-stack";
  };
  # Flake inputs passed to modules as module args. browser-use-skills is also
  # a marketplace entry (see skillSourceInputs).
  inherit (inputs) awesome-claude-skills browser-use-skills;
  # Marketplace flake inputs now live inside nix-claude-code. Surface the
  # full set here so non-Claude consumers (agent-skills, codex, antigravity-cli) can
  # still discover plugins/skills without each consumer having to reach into
  # `nix-claude-code.inputs` themselves. The catalog of marketplace names
  # is owned by nix-claude-code; this attrset just selects what nix-ai
  # still needs. `karpathy-skills` lives in nix-ai (not yet promoted to
  # nix-claude-code) so it's spliced in directly.
  marketplaceInputs = {
    inherit (nix-claude-code.inputs)
      anthropic-agent-skills
      bills-claude-skills
      bitwarden-marketplace
      huggingface-skills
      vct-cribl-pack-validator-skills
      cc-dev-tools
      cc-marketplace
      claude-code-plugins-plus
      claude-code-workflows
      claude-plugins-official
      claude-skills
      lunar-claude
      obsidian-skills
      openai-codex
      axton-obsidian-visual-skills
      superpowers-marketplace
      visual-explainer-marketplace
      ;
  }
  // builtins.mapAttrs (_: name: inputs.${name}) skillSourceInputs;
  # Args a PARTIAL export sets at default priority, so any combination of
  # exports — and a partial one composed with `default` — merges instead of
  # failing "defined multiple times". A consumer that imports
  # `default` alongside a third-party module that itself imports one of the
  # partial exports (nix-ai-open-harness imports `opencode`) hit exactly
  # that on `nix-claude-code`. `default` keeps normal priority and wins.
  partialArgs = builtins.mapAttrs (_: lib.mkDefault);
in
{
  default = {
    imports = [
      # programs.claude.* option schema + settings.json renderer (canonical
      # owner is dryvist/nix-claude-code). Imported here (not from
      # modules/default.nix) so the import list resolves without depending
      # on `_module.args.nix-claude-code` — module imports run before args
      # are wired, which would otherwise cause infinite recursion.
      #
      # nix-claude-code wraps its homeModules with its own marketplaceArgs
      # (claude-cookbooks, claude-code-plugins,
      # fabric-src, plus the 20 marketplace inputs). Those args are
      # transitively available to nix-ai modules — we only set args
      # unique to nix-ai here.
      nix-claude-code.homeModules.claude
      nix-codex.homeModules.approvals
      ../modules/default.nix
      nix-herdr.homeManagerModules.default
      ../modules/herdr
      (import "${nix-agent-sandbox-src}/nix/zcode-job-module.nix")
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          # The dispatcher client is safe on Darwin; keep its connection config opt-in.
          home.packages = lib.optionals (pkgs.stdenv.isDarwin && config.programs.zcode-job.disabled) [
            config.programs.zcode-job.package
          ];
        }
      )
    ];
    _module.args = {
      nixAiRev = self.rev or "dirty";
      inherit
        ai-llm-prompts
        nix-claude-code
        nix-codex
        nix-agy
        nixpkgs-unstable
        nix-claude-code-launcher-src
        nix-codex-launcher-src
        agentNofile
        browser-use-skills
        awesome-claude-skills
        marketplaceInputs
        llm-agents
        herdr-hail-src
        vct-cribl-cli
        vct-splunk-cli
        token-meter-src
        homelab-contracts
        ;
    };
  };

  claude = {
    imports = [
      # Delegate the option set and settings.json renderer to nix-claude-code.
      # nix-claude-code already injects claude-code-plugins, claude-cookbooks,
      # and fabric-src as module
      # args — don't re-set them here or home-manager errors on "defined
      # multiple times".
      nix-claude-code.homeModules.claude
      # MCP runtime is sourced from the MCP sub-flake module so it's
      # available even when Claude is the only homeManagerModule a
      # consumer imports.
      ../modules/mcp/module.nix
      # User-facing values (model, marketplaces, hooks, settings.*) live in
      # this module — nix-claude-code only declares the option schema.
      ../modules/claude-config.nix
      ../modules/agent-launchers.nix
      # userConfig option surface (claude-config reads it via common →
      # permissions). Imported here so standalone consumers get the same
      # option as homeManagerModules.default.
      ../modules/maintainer-profile.nix
    ];
    _module.args = partialArgs {
      inherit
        ai-llm-prompts
        nix-claude-code
        nix-codex
        nix-agy
        nix-claude-code-launcher-src
        nix-codex-launcher-src
        agentNofile
        marketplaceInputs
        llm-agents
        homelab-contracts
        ;
    };
  };

  agent-skills = {
    imports = [ ../modules/agent-skills ];
    _module.args = partialArgs {
      inherit marketplaceInputs awesome-claude-skills;
    };
  };

  mcp = {
    imports = [ ../modules/mcp/module.nix ];
    _module.args = partialArgs {
      inherit homelab-contracts;
    };
  };

  codex = {
    imports = [
      nix-codex.homeModules.approvals
      ../modules/mcp/module.nix
      ../modules/agent-skills
      ../modules/codex
      ../modules/agent-launchers.nix
      ../modules/maintainer-profile.nix
    ];
    _module.args = partialArgs {
      inherit
        ai-llm-prompts
        nix-claude-code
        nix-codex
        nix-agy
        nix-claude-code-launcher-src
        nix-codex-launcher-src
        agentNofile
        llm-agents
        marketplaceInputs
        homelab-contracts
        awesome-claude-skills
        ;
    };
  };

  antigravity-cli = {
    imports = [
      ../modules/mcp/module.nix
      ../modules/agent-skills
      ../modules/antigravity-cli
      ../modules/agent-launchers.nix
      ../modules/maintainer-profile.nix
    ];
    _module.args = partialArgs {
      inherit
        ai-llm-prompts
        nix-claude-code
        nix-codex
        nix-agy
        nix-claude-code-launcher-src
        nix-codex-launcher-src
        agentNofile
        marketplaceInputs
        llm-agents
        homelab-contracts
        awesome-claude-skills
        ;
    };
  };

  antigravity-ide = {
    imports = [
      ../modules/mcp/module.nix
      ../modules/agent-skills
      ../modules/antigravity-ide
      ../modules/maintainer-profile.nix
    ];
    _module.args = partialArgs {
      inherit
        nix-claude-code
        marketplaceInputs
        homelab-contracts
        awesome-claude-skills
        ;
    };
  };

  cecli = {
    imports = [
      ../modules/ai-stack
      ../modules/cecli
    ];
    _module.args = partialArgs {
      inherit homelab-contracts;
    };
  };

  qwen-code = {
    imports = [
      ../modules/ai-stack
      ../modules/mcp/module.nix
      ../modules/agent-skills
      ../modules/qwen-code
      ../modules/maintainer-profile.nix
    ];
    _module.args = partialArgs {
      inherit
        nix-claude-code
        marketplaceInputs
        homelab-contracts
        awesome-claude-skills
        ;
    };
  };

  opencode = {
    # agent-skills nests options under programs.antigravity-cli.skills, which
    # conflicts with upstream home-manager's antigravity-cli module; the full
    # `default` composition disables it via nix-ai's antigravity-cli module,
    # so standalone consumers of these exports must disable it themselves.
    disabledModules = [ "programs/antigravity-cli.nix" ];
    imports = [
      ../modules/mcp/module.nix
      ../modules/agent-skills
      ../modules/litellm-local
      ../modules/ai-stack
      ../modules/opencode
      ../modules/maintainer-profile.nix
    ];
    _module.args = partialArgs {
      inherit
        nix-claude-code
        marketplaceInputs
        llm-agents
        homelab-contracts
        awesome-claude-skills
        ;
    };
  };

  herdr = {
    imports = [
      nix-herdr.homeManagerModules.default
      ../modules/herdr
    ];
    _module.args = partialArgs {
      inherit llm-agents herdr-hail-src;
    };
  };

  maestro = {
    imports = [
      ../modules/maestro
      ../modules/maintainer-profile.nix
    ];
  };
}
