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
  facadeCanarySelected =
    config.programs.aiMcp.facadeCanary || config.programs.aiMcp.facadeCanaryClients.claude;

  # Claude Code's own key allowlist. Every client keeps its own normalizer
  # because the target schemas genuinely differ (Codex takes env_vars and
  # timeouts, opencode fuses command+args, qwen splits url/httpUrl); only the
  # filter/exclude step is shared, via mcpClient.renderServers below.
  normalizeClaudeMcpServer =
    original:
    let
      # Claude reads credential variables in remote headers as empty in some
      # cases. A headersHelper reads this consumer's current environment on
      # every connection, avoiding OAuth discovery and stale session headers.
      envHeaders =
        lib.optional (original.bearer_token_env_var != null && !(original.headers ? Authorization)) {
          name = "Authorization";
          prefix = "Bearer ";
          var = original.bearer_token_env_var;
        }
        ++ lib.mapAttrsToList (name: var: {
          inherit name var;
          prefix = "";
        }) original.env_http_headers;
      server =
        if envHeaders != [ ] then
          original
          // {
            headersHelper = "printf ${lib.escapeShellArg "{${lib.concatMapStringsSep "," (header: "${builtins.toJSON header.name}:${builtins.toJSON "${header.prefix}%s"}") envHeaders}}\\n"} ${
              lib.concatMapStringsSep " " (header: "\"\${${header.var}}\"") envHeaders
            }";
            headers = builtins.removeAttrs original.headers (map (header: header.name) envHeaders);
          }
        else
          original;
    in
    lib.filterAttrs (
      name: value:
      lib.elem name [
        "type"
        "command"
        "args"
        "env"
        "url"
        "headers"
        "headersHelper"
        "disabled"
      ]
      && value != null
      && value != [ ]
      && value != { }
      && !(name == "disabled" && !value)
    ) server;

  mcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    inherit (config.programs.aiMcp) facadeCanary facadeCanaryClients facadeServer;
    excluded = config.programs.claude.excludedMcpServers;
    normalize = normalizeClaudeMcpServer;
    client = "claude";
  };
  mcpServerNames = lib.attrNames mcpServers;

  # Servers held out of the always-on profile (programs.aiMcp.onDemandServers)
  # are still rendered, one ready-to-attach file each, so nothing a session
  # might need becomes unreachable:
  #   claude --mcp-config ~/.claude/mcp-available/zammad.json
  onDemandMcpServers = mcpClient.renderServers {
    enabledServers = config.programs.aiMcp.onDemandEnabledServers;
    inherit (config.programs.aiMcp) facadeCanary facadeCanaryClients facadeServer;
    excluded = config.programs.claude.excludedMcpServers;
    normalize = normalizeClaudeMcpServer;
    client = "claude";
    onDemand = true;
  };

  onDemandMcpFiles = lib.mapAttrs' (name: server: {
    name = ".claude/mcp-available/${name}.json";
    value.text = builtins.toJSON { mcpServers.${name} = server; };
  }) onDemandMcpServers;
  onDemandMcpServerNames = lib.attrNames onDemandMcpServers;
in
{
  # A selected facade owns Claude's final attrsOf map even if downstream
  # modules define programs.claude.mcpServers entries.
  mcpServers = if facadeCanarySelected then lib.mkForce mcpServers else mcpServers;
  inherit mcpServerNames onDemandMcpFiles onDemandMcpServerNames;
  enabledMcpjsonServers =
    if facadeCanarySelected then
      onDemandMcpServerNames
    else
      builtins.attrNames config.programs.aiMcp.onDemandEnabledServers;
}
