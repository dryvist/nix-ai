# Exact configuration projection frozen against the facade selector's merge
# base. The caller supplies Antigravity IDE's native map because that renderer
# did not expose the generated map for checks before this change.
{
  lib,
  codexMcpServers,
  antigravityIdeMcpServers,
}:
hm:
let
  skillRoot =
    if hm.config.programs.agentSkills.root == "codex" then ".codex/skills" else ".agents/skills";
  groupMcpPath = "${skillRoot}/GROUP-MCP.json";
  onDemandFiles = lib.filterAttrs (
    name: _: lib.hasPrefix ".claude/mcp-available/" name
  ) hm.config.home.file;
  opencodeConfig =
    builtins.fromJSON
      hm.config.home.file."${hm.config.programs.opencode.configDir}/opencode.json".source.json;
in
{
  nativeMcpMaps = {
    claude = hm.config.programs.claude.mcpServers;
    codex = codexMcpServers;
    antigravity-cli = hm.config.programs.antigravity-cli.generatedSettings.mcpServers;
    antigravity-ide = antigravityIdeMcpServers;
    "qwen-code" = hm.config.programs.qwen-code.generatedSettings.mcpServers;
    opencode = opencodeConfig.mcp;
  };
  claudeOnDemandFiles = lib.mapAttrs (_: file: file.text) onDemandFiles;
  claudeApprovalNames = hm.config.programs.claude.settings.enabledMcpjsonServers;
  groupMcpServers = hm.config.programs.agentSkills.groupMcpServers;
  groupMcpFile =
    if hm.config.home.file ? ${groupMcpPath} then hm.config.home.file.${groupMcpPath}.text else null;
}
