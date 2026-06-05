# Antigravity CLI Configuration Module
#
# Declarative configuration for Google Antigravity CLI.
# Generates settings.json with shared MCP servers, permissions, commands,
# extensions, and folder trust.
#
# CRITICAL - tools.allowed vs tools.core:
# Per the official Antigravity CLI schema:
# - tools.allowed = "Tool names that bypass the confirmation dialog" (AUTO-APPROVE)
# - tools.core = "Allowlist to RESTRICT built-in tools to a specific set" (LIMITS usage!)
# Always use tools.allowed for auto-approval, NEVER tools.core!
#
# Features:
# - Shared MCP server definitions (normalized for Antigravity format)
# - Auto-generated custom commands from agentsmd
# - Extension management (~/.gemini/antigravity-cli/extensions/)
# - settings.json deep-merge activation (preserves auth tokens)
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.antigravity-cli;
in
{
  imports = [
    ./options.nix
    ./settings.nix
    ./components.nix
    ./extensions.nix
  ];

  config = lib.mkIf cfg.enable {
    # Ensure directory structure exists
    home.file.".gemini/antigravity-cli/.keep".text = ''
      # Managed by Nix - programs.antigravity-cli module
    '';
  };
}
