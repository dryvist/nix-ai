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
  claude = import ./formatters/claude.nix { inherit lib flattenCommands; };
  gemini = import ./formatters/gemini.nix { inherit lib flattenCommands; };
  antigravity-ide = import ./formatters/antigravity-ide.nix { inherit lib flattenCommands; };
  copilot = import ./formatters/copilot.nix { inherit lib flattenCommands; };
  codex = import ./formatters/codex.nix { inherit lib flattenCommands; };
in
{
  inherit
    claude
    gemini
    copilot
    codex
    utils
    ;

  "antigravity-cli" = gemini;
  "antigravity-ide" = antigravity-ide;
}
