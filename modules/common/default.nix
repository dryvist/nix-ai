# AI CLI Common Module
#
# Provides unified permission definitions and formatters for all AI CLI tools.
# This is the single source of truth for command permissions.
#
# USAGE:
#   let
#     aiCommon = import ./common { inherit lib config nix-claude-code; };
#     geminiAllowedTools = aiCommon.formatters.gemini.formatAllowedTools aiCommon.permissions;
#   in { ... }
#
# CRITICAL - Gemini tools.allowed vs tools.core:
# Per the official Gemini CLI schema:
# - tools.allowed = "Tool names that bypass the confirmation dialog" (AUTO-APPROVE)
# - tools.core = "Allowlist to RESTRICT built-in tools" (LIMITS usage!)
# Always use formatAllowedTools for auto-approval, NEVER for core!
#
# EXPORTS:
# - permissions: Tool-agnostic command definitions
# - formatters: Tool-specific formatting functions

{
  lib,
  config,
  nix-claude-code,
  excludeDenyCategories ? [ ],
  excludeDenyCommands ? [ ],
  ...
}:

{
  # Unified permission definitions
  permissions = import ./permissions.nix {
    inherit
      lib
      config
      nix-claude-code
      excludeDenyCategories
      excludeDenyCommands
      ;
  };

  # Tool-specific formatters
  formatters = import ./formatters.nix { inherit lib; };
}
