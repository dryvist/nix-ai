# Merge user settings, then keep the selected whole-set MCP map authoritative.
{
  lib,
  settings,
  extraSettings,
  mcpServers,
  selected,
}:
let
  mergedSettings = lib.recursiveUpdate settings extraSettings;
in
if selected then mergedSettings // { mcp = mcpServers; } else mergedSettings
