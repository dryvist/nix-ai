# Claude Code MCP rendering
#
# Split out of claude-config.nix: every client renders the shared catalog
# through its own key allowlist, and Claude additionally renders the on-demand
# tier to one attachable file per server. Kept here so claude-config.nix stays
# under the org file-size limit — the repo's convention is to split a file that
# drifts past the threshold, never to raise the threshold.
{
  lib,
  config,
}:
let
  mcpClient = import ../mcp/client.nix { inherit lib; };

  # Claude Code's own key allowlist. Every client keeps its own normalizer
  # because the target schemas genuinely differ (Codex takes env_vars and
  # timeouts, opencode fuses command+args, qwen splits url/httpUrl); only the
  # filter/exclude step is shared, via mcpClient.renderServers below.
  normalizeClaudeMcpServer =
    server:
    lib.filterAttrs (
      name: value:
      lib.elem name [
        "type"
        "command"
        "args"
        "env"
        "url"
        "headers"
        "disabled"
      ]
      && value != null
      && value != [ ]
      && value != { }
      && !(name == "disabled" && !value)
    ) server;

  mcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    excluded = config.programs.claude.excludedMcpServers;
    normalize = normalizeClaudeMcpServer;
    client = "claude";
  };

  # Servers held out of the always-on profile (programs.aiMcp.onDemandServers)
  # are still rendered, one ready-to-attach file each, so nothing a session
  # might need becomes unreachable:
  #   claude --mcp-config ~/.claude/mcp-available/zammad.json
  onDemandMcpServers = mcpClient.renderServers {
    enabledServers = config.programs.aiMcp.onDemandEnabledServers;
    excluded = config.programs.claude.excludedMcpServers;
    normalize = normalizeClaudeMcpServer;
    client = "claude";
  };

  onDemandMcpFiles = lib.mapAttrs' (name: server: {
    name = ".claude/mcp-available/${name}.json";
    value.text = builtins.toJSON { mcpServers.${name} = server; };
  }) onDemandMcpServers;
in
{
  inherit mcpServers onDemandMcpFiles;
}
