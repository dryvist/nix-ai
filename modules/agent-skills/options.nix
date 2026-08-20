# Agent Skills Module Options
#
# Declarative options for shared skills consumed by multiple AI CLIs.
{ lib, ... }:

let
  componentModule = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      source = lib.mkOption { type = lib.types.path; };
    };
  };
in
{
  options.programs.agentSkills = {
    enable = lib.mkEnableOption "shared skill deployment for AI harnesses";

    root = lib.mkOption {
      type = lib.types.enum [
        "codex"
        "agents"
      ];
      default = "codex";
      description = ''
        Canonical skill root. "codex" deploys to ~/.codex/skills; "agents"
        deploys to ~/.agents/skills for cross-harness sharing. Codex discovers
        both locations natively, so select exactly one instead of linking them
        together and making Codex scan the same skills twice.
      '';
    };

    opencodeConfigDir = lib.mkOption {
      type = lib.types.str;
      default = ".config/opencode";
      description = ''
        OpenCode config directory (relative to $HOME) that the registry
        symlinks skills and AGENTS.md into. Kept as the harness's own option so
        this module stays standalone (it does not import programs.opencode);
        the full stack wires it from programs.opencode.configDir in
        modules/default.nix.
      '';
    };

    fromFlakeInputs = lib.mkOption {
      type = lib.types.listOf componentModule;
      default = [ ];
      description = "Skills sourced from flake inputs (immutable, from Nix store)";
    };

    local = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Local skill files (name -> path to SKILL.md; the containing skill directory is deployed)";
    };

    # Categories group the generated INDEX.md so a reader can find a skill by
    # domain instead of scanning one flat list. Expressed as category -> skill
    # names rather than a per-skill field because nearly every skill is
    # auto-discovered from a flake input: there is no per-entry place to write
    # a category, so the mapping has to live somewhere central regardless.
    # A skill named under several categories is listed under each of them —
    # that is the whole multi-membership feature, and it costs nothing.
    # Names that match no deployed skill are ignored, so a category can be
    # written ahead of the input that supplies its skill.
    categories = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        research = [
          "github-code-search"
          "last30days"
        ];
        workspace = [ "file-organizer" ];
      };
      description = "Category name -> skill names. A skill may appear in more than one category.";
    };
  };
}
