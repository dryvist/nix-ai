# Read each harness's actual generated MCP map, not its name-only summary.
hm: {
  claude = hm.config.programs.claude.mcpServers;
  codex = hm.config.programs.codex.generatedMcpServers;
  antigravity-cli = hm.config.programs.antigravity-cli.generatedSettings.mcpServers;
  antigravity-ide = hm.config.programs.antigravity-ide.generatedMcpServers;
  "qwen-code" = hm.config.programs.qwen-code.generatedSettings.mcpServers;
  opencode =
    (builtins.fromJSON
      hm.config.home.file."${hm.config.programs.opencode.configDir}/opencode.json".source.json
    ).mcp;
}
