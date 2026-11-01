# OpenCode ignores Claude's invocation flag. Native commands load manual
# workflows explicitly while skill permissions hide them from model selection.
{
  lib,
  skillRoot,
  userInvokedSkills,
  homeDirectory,
}:
lib.listToAttrs (
  map (skill: {
    inherit (skill) name;
    value = {
      description = "Run the ${skill.name} skill";
      template = ''
        Follow the ${skill.name} skill in @${homeDirectory}/${skillRoot}/${skill.name}/SKILL.md.
        Load reusable skills through the native skill tool; resolve supporting
        files relative to the referenced skill directory.

        User arguments: $ARGUMENTS
      '';
    };
  }) userInvokedSkills
)
