# Claude MCP and gateway configuration
#
# Keep the per-client MCP options, gateway caller identities, and rendered
# files together so the main Claude values module stays below the file-size cap.
{
  config,
  lib,
  ...
}:

let
  # Also used below for mkClientOptions; the rendering itself lives in
  # claude/mcp-render.nix to keep this file under the org file-size limit.
  mcpClient = import ./mcp/client.nix { inherit lib; };
  claudeMcp = import ./claude/mcp-render.nix { inherit lib config; };
  inherit (claudeMcp) mcpServers onDemandMcpFiles zaiMcpServers;
in
{
  # excludedMcpServers + mcpServerNames come from the shared MCP client helper,
  # same as every other client. Declared here rather than in nix-claude-code
  # because the shared catalog and its per-client exclude semantics are nix-ai's
  # concern; nix-claude-code owns only the rendering of programs.claude.mcpServers.
  options.programs.claude = mcpClient.mkClientOptions "Claude Code" // {
    zaiCallerId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Caller ID used by the claude-zai launcher.";
    };

    zaiCallerKeyEnv = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Optional environment-variable override for the claude-zai caller key.";
    };

    zaiRenderedMcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      readOnly = true;
      internal = true;
      description = "Normalized MCP configuration emitted for claude-zai.";
    };
  };

  config = {
    programs.claude = {
      callerId = "claude-code";
      zaiCallerId = "claude-zai";
      renderedMcpServers = mcpServers;
      zaiRenderedMcpServers = zaiMcpServers;

      # MCP Servers - deployed to ~/.claude.json via home.activation.
      # Shared definitions are owned by modules/mcp and rendered per-client here.
      inherit mcpServers;
      mcpServerNames = lib.attrNames mcpServers;

      # A repository's `.mcp.json` written by `agent-skill-groups link` only
      # ever names catalog servers from the on-demand tier, so approve
      # exactly those without the per-project prompt. Anything else in a
      # `.mcp.json` still prompts, by name.
      settings.enabledMcpjsonServers = builtins.attrNames config.programs.aiMcp.onDemandEnabledServers;
    };

    home.file = onDemandMcpFiles // {
      ".claude/mcp-zai.json".text = builtins.toJSON { mcpServers = zaiMcpServers; };
    };
  };
}
