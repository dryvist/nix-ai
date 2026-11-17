# agentops skills reach the shared skill root and win the names they share.
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  deployedPaths = hmConfig.config.programs.agentSkills.deployedSkillPaths;
  # Names agentops shares with mattpocock-skills and project-standards.
  sharedNames = [
    "implement"
    "research"
    "skill-builder"
    "triage"
  ];
  agentopsGlobal = [
    "agy-native"
    "codex-exec"
    "doc"
    "orchestrate"
    "plan"
    "skill-eval"
  ];
in
{
  agentops-skills =
    # Only the agentops SKILL.md carries `skill_api_version`.
    assert
      builtins.all (
        name:
        pkgs.lib.hasInfix "skill_api_version" (
          builtins.readFile "${deployedPaths.".codex/skills/${name}"}/SKILL.md"
        )
      ) sharedNames
      || throw "Skills shared with another input must deploy from agentops: ${builtins.toJSON sharedNames}";
    assert
      builtins.all (name: builtins.hasAttr ".codex/skills/${name}" deployedPaths) agentopsGlobal
      || throw "agentops skills missing from the skill root: ${builtins.toJSON agentopsGlobal}";
    helpers.mkMarker "check-agentops-skills" "agentops skills deploy to the skill root and win the names they share";
}
