# Gemini CLI User-Prompted Commands (ASK Rules)
#
# Gemini CLI now supports "ask_user" decision via the Policy Engine.
# Commands here require explicit user confirmation before execution.
#
# Uses unified permission definitions from ai-cli/common/permissions.nix
# with Gemini-specific formatting via formatters.nix.

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
  askRules = formatters."antigravity-cli".formatAskRules permissions;
}
