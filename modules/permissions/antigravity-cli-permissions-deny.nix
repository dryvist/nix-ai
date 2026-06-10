# Gemini CLI Permanently Blocked Commands (DENY Rules)
#
# Uses unified permission definitions from ai-cli/common/permissions.nix
# with Gemini-specific formatting via formatters.nix.
#
# Policy Engine: Exports rule attrsets with decision="deny" for policyPaths TOML.
# Legacy: Exports ShellTool(cmd) lists for backward compatibility in tests.

{
  config,
  lib,
  nix-claude-code,
  ...
}:

let
  aiCommon = import ../common { inherit lib config nix-claude-code; };
  inherit (aiCommon) permissions formatters;
in
{
  # Policy Engine rules (primary)
  denyRules = formatters."antigravity-cli".formatDenyRules permissions;

  # Legacy format (kept for CI lib output and regression tests)
  excludeTools = formatters."antigravity-cli".formatExcludeTools permissions;
}
