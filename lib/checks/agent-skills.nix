# Agent Skills module regression tests
{ pkgs, hmConfig }:
let
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
  agent-skills-options-regression =
    let
      expectedOptions = [
        "enable"
        "fromFlakeInputs"
        "local"
      ];
      actualOptions = builtins.attrNames cfg;
      missingOptions = builtins.filter (o: !(builtins.elem o actualOptions)) expectedOptions;
    in
    assert
      missingOptions == [ ] || throw "Missing Agent Skills options: ${builtins.toJSON missingOptions}";
    pkgs.runCommand "check-agent-skills-options-regression" { } ''
      echo "Agent Skills option regression: ${toString (builtins.length expectedOptions)} options verified"
      touch $out
    '';

  # Verify evaluated config values match expected defaults.
  agent-skills-defaults-regression =
    let
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
      failures = builtins.filter (c: c.actual != c.expected) checks;
      failureMsg = builtins.concatStringsSep "\n" (
        map (
          c: "  ${c.name}: expected ${builtins.toJSON c.expected}, got ${builtins.toJSON c.actual}"
        ) failures
      );
    in
    assert failures == [ ] || throw "Agent Skills default value regression:\n${failureMsg}";
    pkgs.runCommand "check-agent-skills-defaults-regression" { } ''
      echo "Agent Skills defaults regression: ${toString (builtins.length checks)} critical defaults verified"
      touch $out
    '';

  # Validate module output wiring for ~/.agents ownership.
  agent-skills-home-files =
    let
      keepFile = hmConfig.config.home.file.".agents/.keep".text;
      # SKILL.md presence used to be verified via builtins.pathExists on
      # ${home.file.X.source}/SKILL.md, but that requires the wrap derivation
      # to be realised, which is incompatible with the .github reusable
      # workflow's `nix flake check --all-systems --no-build` (used to keep
      # the linux runner from exhausting disk on cross-platform substitution).
      # SKILL.md presence is guaranteed by the heredoc in
      # modules/agent-skills/default.nix (wrappedSkillDir).
    in
    assert keepFile != "" || throw "Agent Skills .agents/.keep file is empty (module not loaded)";
    assert builtins.length managedSkillEntries > 0 || throw "No managed .agents skill entries found";
    assert
      legacySkillFileEntries == [ ]
      || throw "Agent Skills must deploy skill directories, not SKILL.md files: ${builtins.toJSON legacySkillFileEntries}";
    pkgs.runCommand "check-agent-skills-home-files" { } ''
      echo "Agent Skills home.file wiring: ${toString (builtins.length managedSkillEntries)} managed skill entries"
      touch $out
    '';
}
