# GitHub Copilot CLI Recommended Deny Tools (DENY List)
#
# Uses unified permission definitions from ai-cli/common/permissions.nix.
#
# COPILOT CLI DENY MODEL:
# Copilot doesn't have a config-based deny list. Instead, use CLI flags:
#   copilot --deny-tool 'shell(rm -rf /)'
#
# This file provides the recommended --deny-tool flags based on the
# unified permission definitions.
#
# SINGLE SOURCE OF TRUTH:
# Command definitions are in ai-cli/common/permissions.nix
# This file only formats them for Copilot's --deny-tool syntax.
#
# USAGE EXAMPLE:
# Build a deny-tool command string:
#
#   copilot \
#     --deny-tool 'shell(rm -rf /)' \
#     --deny-tool 'shell(sudo rm)' \
#     --deny-tool 'shell(curl -X POST)'
#
# Or create a shell alias in your .zshrc:
#   alias copilot-safe='copilot --deny-tool "shell(rm -rf /)" --deny-tool "shell(sudo rm)"'

{
  config,
  lib,
  nix-claude-code,
  ...
}:

let
  # Import unified permissions and formatters
  aiCommon = import ../common { inherit lib config nix-claude-code; };
  inherit (aiCommon) permissions formatters;

in
{
  # Recommended --deny-tool flags
  # Usage: copilot --deny-tool 'shell(rm -rf /)'
  recommendedDenyTools = formatters.copilot.formatDenyFlags permissions;
}
