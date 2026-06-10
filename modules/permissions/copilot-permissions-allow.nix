# GitHub Copilot CLI Trusted Directories (ALLOW List)
#
# Uses unified permission definitions from ai-cli/common/permissions.nix.
#
# COPILOT CLI PERMISSION MODEL:
# - trusted_folders: List of directories where Copilot can operate (config.json)
# - --allow-tool / --deny-tool: CLI flags for runtime permission control
#
# SINGLE SOURCE OF TRUTH:
# Directory definitions are in ai-cli/common/permissions.nix
# This file only extracts the relevant directories.
#
# NOTE: Unlike Claude Code and Gemini CLI, Copilot CLI's config.json only
# contains trusted_folders. Permission controls are managed via command-line
# flags (--allow-tool, --deny-tool) which must be specified at runtime.

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
  # Export trusted_folders list for config.json
  trusted_folders = formatters.copilot.getTrustedFolders permissions;
}
