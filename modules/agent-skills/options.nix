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
    enable = lib.mkEnableOption "shared skill deployment to ~/.agents/skills";

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
  };
}
