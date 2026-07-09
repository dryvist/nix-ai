{
  ai-assistant-instructions,
  nix-claude-code,
  karpathy-skills,
  nixpkgs-unstable,
  dashmotion,
  ponytail,
  last30days-skill,
}:
let
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
    inherit karpathy-skills;
    inherit dashmotion;
    inherit ponytail;
    inherit last30days-skill;
  };
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
      # (ai-assistant-instructions, claude-cookbooks, claude-code-plugins,
      # fabric-src, plus the 20 marketplace inputs). Those args are
      # transitively available to nix-ai modules — we only set args
      # unique to nix-ai here.
      nix-claude-code.homeModules.claude
      ../modules/default.nix
    ];
    _module.args = {
      inherit
        nix-claude-code
        marketplaceInputs
        nixpkgs-unstable
        ;
    };
  };

  claude = {
    imports = [
      # Delegate the option set and settings.json renderer to nix-claude-code.
      # nix-claude-code already injects ai-assistant-instructions,
      # claude-code-plugins, claude-cookbooks, and fabric-src as module
      # args — don't re-set them here or home-manager errors on "defined
      # multiple times".
      nix-claude-code.homeModules.claude
      # MCP runtime (doppler-mcp, splunk-mcp-connect) is sourced from the MCP
      # sub-flake module so it's available even when Claude is the only
      # homeManagerModule a consumer imports.
      ../modules/mcp/module.nix
      # User-facing values (model, marketplaces, hooks, settings.*) live in
      # this module — nix-claude-code only declares the option schema.
      ../modules/claude-config.nix
    ];
    _module.args = {
      inherit
        nix-claude-code
        marketplaceInputs
        ;
    };
  };

  agent-skills = {
    imports = [ ../modules/agent-skills ];
    _module.args = {
      inherit marketplaceInputs;
    };
  };

  mcp = {
    imports = [ ../modules/mcp ];
  };

  codex = {
    imports = [
      ../modules/mcp
      ../modules/agent-skills
      ../modules/codex
    ];
    _module.args = {
      inherit
        ai-assistant-instructions
        nix-claude-code
        marketplaceInputs
        ;
    };
  };

  antigravity-cli = {
    imports = [
      ../modules/mcp
      ../modules/agent-skills
      ../modules/antigravity-cli
    ];
    _module.args = {
      inherit
        ai-assistant-instructions
        nix-claude-code
        marketplaceInputs
        ;
    };
  };

  antigravity-ide = {
    imports = [
      ../modules/mcp
      ../modules/agent-skills
      ../modules/antigravity-ide
    ];
    _module.args = {
      inherit
        nix-claude-code
        marketplaceInputs
        ;
    };
  };

  cecli = {
    imports = [
      ../modules/ai-stack
      ../modules/cecli
    ];
    _module.args = {
      inherit ai-assistant-instructions;
    };
  };

  qwen-code = {
    imports = [
      ../modules/ai-stack
      ../modules/mcp
      ../modules/agent-skills
      ../modules/qwen-code
    ];
    _module.args = {
      inherit
        ai-assistant-instructions
        marketplaceInputs
        ;
    };
  };

  maestro = {
    imports = [ ../modules/maestro ];
  };
}
