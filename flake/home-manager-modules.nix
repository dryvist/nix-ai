{
  ai-assistant-instructions,
  marketplaceInputs,
  claude-code-plugins,
  claude-cookbooks,
  pal-mcp-server,
  fabric-src,
  nixpkgs-unstable,
}:
{
  default = {
    imports = [ ../modules/default.nix ];
    _module.args = {
      inherit
        ai-assistant-instructions
        marketplaceInputs
        claude-code-plugins
        claude-cookbooks
        pal-mcp-server
        fabric-src
        nixpkgs-unstable
        ;
    };
  };

  claude = {
    imports = [
      ../modules/claude
      # PAL/MCP runtime previously lived in modules/claude/pal-models.nix;
      # now sourced from the MCP sub-flake module so it's available even
      # when Claude is the only homeManagerModule a consumer imports.
      ../modules/mcp/module.nix
    ];
    _module.args = {
      inherit
        ai-assistant-instructions
        marketplaceInputs
        claude-code-plugins
        claude-cookbooks
        pal-mcp-server
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
        marketplaceInputs
        ;
    };
  };

  gemini = {
    imports = [
      ../modules/mcp
      ../modules/agent-skills
      ../modules/gemini
    ];
    _module.args = {
      inherit
        ai-assistant-instructions
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
      ../modules/qwen-code
    ];
    _module.args = {
      inherit ai-assistant-instructions;
    };
  };

  maestro = {
    imports = [ ../modules/maestro ];
  };
}
