# Gemini CLI Auto-Approved Commands (ALLOW Rules)
#
# Uses unified permission definitions from ai-cli/common/permissions.nix
# with Gemini-specific formatting via formatters.nix.
#
# Policy Engine: Exports rule attrsets with decision="allow" for policyPaths TOML.
# Legacy: Exports ShellTool(cmd) lists for backward compatibility in tests.

{
  config,
  lib,
  ai-assistant-instructions,
  ...
}:

let
  aiCommon = import ../common { inherit lib config ai-assistant-instructions; };
  inherit (aiCommon) permissions formatters;
in
{
  # Policy Engine rules (primary)
  allowRules = formatters."antigravity-cli".formatAllowRules permissions;

  # Legacy format (kept for CI lib output and regression tests)
  allowedTools = formatters."antigravity-cli".formatAllowedTools permissions;
}
