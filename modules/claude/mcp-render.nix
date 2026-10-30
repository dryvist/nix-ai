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
  #
  # typed = true is for programs.claude.mcpServers, whose nix-claude-code
  # submodule has no headersHelper, so credentials are interpolated into
  # headers. If Claude reads an empty value, the gateway rejects the call, so
  # the failure is closed. typed = false is for the JSON files, which keep the
  # helper.
  normalizeClaudeMcpServer =
    { typed }:
    original:
    let
      headerEnv =
        lib.optional (original.bearer_token_env_var != null && !(original.headers ? Authorization)) {
          name = "Authorization";
          prefix = "Bearer ";
          env = original.bearer_token_env_var;
        }
        ++ lib.optional (original.gatewayKeyEnv != null) {
          name = "X-Agent-Key";
          prefix = "";
          env = original.gatewayKeyEnv;
        };
      headerFormat = builtins.toJSON (
        lib.listToAttrs (
          map (header: {
            inherit (header) name;
            value = "${header.prefix}%s";
          }) headerEnv
        )
      );
      inlineHeaders = lib.listToAttrs (
        map (header: {
          inherit (header) name;
          value = header.prefix + "\${" + header.env + "}";
        }) headerEnv
      );
      # Claude reads credential variables in remote headers as empty in some
      # cases. A headersHelper reads only this caller's variables on each
      # connection, keeping the secret out of the rendered config.
      server =
        if typed then
          if headerEnv != [ ] then original // { headers = original.headers // inlineHeaders; } else original
        else if headerEnv != [ ] then
          original
          // {
            headersHelper =
              "printf "
              + lib.escapeShellArg "${headerFormat}\\n"
              + " "
              + lib.concatStringsSep " " (map (header: "\"\${" + header.env + "}\"") headerEnv);
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
    excluded = config.programs.claude.excludedMcpServers;
    normalize = normalizeClaudeMcpServer { typed = true; };
    client = "claude";
    callerId = config.programs.claude.callerId;
    callerKeyEnvOverride = config.programs.claude.callerKeyEnv;
    callerIds = config.programs.aiMcp.callerIds;
  };

  # Servers held out of the always-on profile (programs.aiMcp.onDemandServers)
  # are still rendered, one ready-to-attach file each, so nothing a session
  # might need becomes unreachable:
  #   claude --mcp-config ~/.claude/mcp-available/zammad.json
  onDemandMcpServers = mcpClient.renderServers {
    enabledServers = config.programs.aiMcp.onDemandEnabledServers;
    excluded = config.programs.claude.excludedMcpServers;
    normalize = normalizeClaudeMcpServer { typed = false; };
    client = "claude";
    callerId = config.programs.claude.callerId;
    callerKeyEnvOverride = config.programs.claude.callerKeyEnv;
    callerIds = config.programs.aiMcp.callerIds;
  };

  zaiMcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    excluded = config.programs.claude.excludedMcpServers;
    normalize = normalizeClaudeMcpServer { typed = false; };
    client = "claude-zai";
    callerId = config.programs.claude.zaiCallerId;
    callerKeyEnvOverride = config.programs.claude.zaiCallerKeyEnv;
    callerIds = config.programs.aiMcp.callerIds;
  };

  onDemandMcpFiles = lib.mapAttrs' (name: server: {
    name = ".claude/mcp-available/${name}.json";
    value.text = builtins.toJSON { mcpServers.${name} = server; };
  }) onDemandMcpServers;
in
{
  inherit mcpServers onDemandMcpFiles zaiMcpServers;
}
