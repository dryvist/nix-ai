# Agent Skills group-gating regression test.
#
# Split out of agent-skills.nix to stay under the per-file size gate; the
# grouped fixture below is used by nothing else.
{
  pkgs,
  mkHmConfig,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  # Group-gated evaluation fixture: only the `core` group's skills may deploy.
  # Members name real discovered skills plus one that matches nothing (must be
  # ignored, same forward-tolerance as categories).
  hmConfigAgentSkillsGrouped = mkHmConfig [
    {
      programs.agentSkills = {
        root = "agents";
        groups.core = [
          "autoresearch"
          "premium-agent-orchestration"
          "not-a-real-skill"
        ];
        # Not active: must still appear in GROUPS.json for repo-level linking.
        groups.other = [ "ponytail" ];
        activeGroups = [ "core" ];
      };
    }
  ];
  # INDEX.md and GROUPS.json are generated manifests, not skill directories.
  manifests = [
    ".agents/skills/INDEX.md"
    ".agents/skills/GROUPS.json"
  ];
  isSkillEntry =
    root: name: builtins.match "${root}/[^/]+" name != null && !(builtins.elem name manifests);
in
{
  # Group gating: activeGroups deploys exactly the union of the named groups.
  # The grouped fixture activates only `core` = [ autoresearch kaizen
  # not-a-real-skill ]; the phantom member must be ignored, every other
  # discovered skill (e.g. `why` from the same input as kaizen) must NOT
  # deploy, and the INDEX manifest must shrink to match — the manifest is what
  # loader-less harnesses read, so a stale entry there is a silent lie.
  agent-skills-groups =
    let
      groupedFiles = hmConfigAgentSkillsGrouped.config.home.file;
      # Skill directories are linked directly at their store paths, not via
      # home.file (modules/lib/stable-links.nix), so the delivery map is the
      # source of truth for what gets deployed.
      groupedSkillEntries = builtins.filter (n: isSkillEntry ".agents/skills" n) (
        builtins.attrNames hmConfigAgentSkillsGrouped.config.programs.agentSkills.deployedSkillPaths
      );
      groupedIndex = groupedFiles.".agents/skills/INDEX.md".text;
      groupedGroups = builtins.fromJSON (
        builtins.unsafeDiscardStringContext groupedFiles.".agents/skills/GROUPS.json".text
      );
    in
    assert
      builtins.elem ".agents/skills/autoresearch" groupedSkillEntries
      || throw "group gating dropped a core-group skill (autoresearch)";
    assert
      builtins.elem ".agents/skills/premium-agent-orchestration" groupedSkillEntries
      || throw "group gating dropped a core-group skill (premium-agent-orchestration)";
    assert
      !(builtins.elem ".agents/skills/writing-clearly-and-concisely" groupedSkillEntries)
      || throw "group gating deployed a skill outside the active groups (writing-clearly-and-concisely)";
    assert
      builtins.length groupedSkillEntries == 2
      || throw "group gating must deploy exactly the active groups' skills, got ${builtins.toJSON groupedSkillEntries}";
    assert
      builtins.match ".*writing-clearly-and-concisely.*" groupedIndex == null
      || throw "INDEX.md lists a skill the group gate excluded (writing-clearly-and-concisely)";
    assert
      (groupedGroups.other or { }) ? ponytail
      || throw "GROUPS.json must list inactive groups' skills so a repository can link them";
    assert
      !((groupedGroups.core or { }) ? not-a-real-skill)
      || throw "GROUPS.json must not list a group member that matches no skill";
    helpers.mkMarker "check-agent-skills-groups" "Agent Skills group gating: ${toString (builtins.length groupedSkillEntries)} skills from active groups only";
}
