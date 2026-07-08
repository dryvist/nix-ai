# Agent Skills module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.agentSkills;
  homeFileNames = builtins.attrNames hmConfig.config.home.file;
  managedSkillEntries = builtins.filter (
    n: builtins.match "^\\.agents/skills/[^/]+$" n != null
  ) homeFileNames;
  legacySkillFileEntries = builtins.filter (
    n: builtins.match "^\\.agents/skills/.+/SKILL\\.md$" n != null
  ) homeFileNames;
in
{
  # Verify all expected Agent Skills option paths exist.
  agent-skills-options-regression = helpers.mkOptionsRegression {
    label = "Agent Skills";
    checkName = "check-agent-skills-options-regression";
    inherit cfg;
    expectedOptions = [
      "enable"
      "fromFlakeInputs"
      "local"
    ];
  };

  # Verify evaluated config values match expected defaults.
  agent-skills-defaults-regression = helpers.mkDefaultsRegression {
    label = "Agent Skills";
    checkName = "check-agent-skills-defaults-regression";
    checks = [
      {
        name = "agentSkills.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "agentSkills.fromFlakeInputs.populated";
        actual = builtins.length cfg.fromFlakeInputs > 0;
        expected = true;
      }
      {
        name = "agentSkills.local";
        actual = cfg.local;
        expected = { };
      }
    ];
  };

  # Validate module output wiring for ~/.agents ownership.
  agent-skills-home-files =
    let
      keepFile = hmConfig.config.home.file.".agents/.keep".text;
      missingSkillFiles = builtins.filter (
        n: !(builtins.pathExists "${hmConfig.config.home.file.${n}.source}/SKILL.md")
      ) managedSkillEntries;
    in
    assert keepFile != "" || throw "Agent Skills .agents/.keep file is empty (module not loaded)";
    assert builtins.length managedSkillEntries > 0 || throw "No managed .agents skill entries found";
    assert
      legacySkillFileEntries == [ ]
      || throw "Agent Skills must deploy skill directories, not SKILL.md files: ${builtins.toJSON legacySkillFileEntries}";
    assert
      missingSkillFiles == [ ]
      || throw "Agent Skills directory entries missing SKILL.md: ${builtins.toJSON missingSkillFiles}";
    helpers.mkMarker "check-agent-skills-home-files" "Agent Skills home.file wiring: ${toString (builtins.length managedSkillEntries)} managed skill entries";
}
