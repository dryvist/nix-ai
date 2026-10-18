# AI CLI Permission Formatters Entrypoint
#
# Transforms tool-agnostic command definitions into tool-specific formats.
# Decomposed into tool-specific modules under formatters/.
{ lib }:

let
  # Import utilities and helper functions
  utils = import ./formatters/utils.nix { inherit lib; };
  inherit (utils) flattenCommands;

  # Import tool-specific formatters
  claude = import ./formatters/claude.nix { inherit flattenCommands; };
  gemini = import ./formatters/gemini.nix { inherit flattenCommands; };
  antigravity-ide = import ./formatters/antigravity-ide.nix { inherit flattenCommands; };
  copilot = import ./formatters/copilot.nix { inherit flattenCommands; };
  codex = import ./formatters/codex.nix { inherit lib flattenCommands; };
  opencode = import ./formatters/opencode.nix { inherit lib flattenCommands; };
  qwen = import ./formatters/qwen.nix { inherit flattenCommands; };
in
{
  inherit
    claude
    gemini
    copilot
    codex
    opencode
    qwen
    utils
    ;

  "antigravity-cli" = gemini;
  "antigravity-ide" = antigravity-ide;
}
