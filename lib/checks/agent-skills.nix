# Agent Skills module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.agentSkills;
  homeFileNames = builtins.attrNames hmConfig.config.home.file;
  # INDEX.md is the generated manifest, not a skill directory — exclude it.
  managedSkillEntries = builtins.filter (
    n: builtins.match "^\\.agents/skills/[^/]+$" n != null && n != ".agents/skills/INDEX.md"
  ) homeFileNames;
  legacySkillFileEntries = builtins.filter (
    n: builtins.match "^\\.agents/skills/.+/SKILL\\.md$" n != null
  ) homeFileNames;
  indexText = hmConfig.config.home.file.".agents/skills/INDEX.md".text;
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
      "categories"
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
      # `local` is no longer empty: file-organizer's upstream layout matches no
      # discovery pattern, so it is wired by path. Assert the entry is present
      # rather than pinning the whole attrset — a second local skill should not
      # break this check, but silently losing this one should.
      {
        name = "agentSkills.local.file-organizer";
        actual = cfg.local ? file-organizer;
        expected = true;
      }
      {
        name = "agentSkills.categories.populated";
        actual = cfg.categories != { };
        expected = true;
      }
    ];
  };

  # Validate module output wiring for ~/.agents ownership.
  agent-skills-home-files =
    let
      keepFile = hmConfig.config.home.file.".agents/.keep".text;
      # Same registry the module fans out from — the check cannot drift.
      harnesses = import ../../modules/agent-skills/harnesses.nix;
      sharedSkillLinks = builtins.attrValues harnesses.skills;
      missingSharedLinks = builtins.filter (
        n: !(builtins.hasAttr n hmConfig.config.home.file)
      ) sharedSkillLinks;
      # AGENTS.md fan-out: each tool's native global path → ~/.agents/AGENTS.md
      sharedAgentsMdLinks = builtins.attrValues harnesses.agentsMd;
      missingAgentsMdLinks = builtins.filter (
        n: !(builtins.hasAttr n hmConfig.config.home.file)
      ) sharedAgentsMdLinks;
      # home.file entries are submodules, so the `source` attribute is always
      # present — hasAttr is a no-op. An entry with no real source throws on
      # access ("option used but not defined"), so probe with tryEval instead.
      missingSkillSources = builtins.filter (
        n: !(builtins.tryEval hmConfig.config.home.file.${n}.source).success
      ) managedSkillEntries;
      skillFileSources = builtins.filter (
        n:
        let
          entry = hmConfig.config.home.file.${n};
        in
        entry ? source && pkgs.lib.hasSuffix "/SKILL.md" (toString entry.source)
      ) managedSkillEntries;
    in
    assert keepFile != "" || throw "Agent Skills .agents/.keep file is empty (module not loaded)";
    assert builtins.length managedSkillEntries > 0 || throw "No managed .agents skill entries found";
    assert
      legacySkillFileEntries == [ ]
      || throw "Agent Skills must deploy skill directories, not SKILL.md files: ${builtins.toJSON legacySkillFileEntries}";
    assert
      missingSkillSources == [ ]
      || throw "Agent Skills directory entries missing source: ${builtins.toJSON missingSkillSources}";
    assert
      skillFileSources == [ ]
      || throw "Agent Skills must source skill directories, not SKILL.md files: ${builtins.toJSON skillFileSources}";
    assert
      missingSharedLinks == [ ]
      || throw "Agent Skills shared links missing: ${builtins.toJSON missingSharedLinks}";
    assert
      missingAgentsMdLinks == [ ]
      || throw "Agent Skills AGENTS.md harness links missing: ${builtins.toJSON missingAgentsMdLinks}";
    assert
      builtins.elem ".agents/skills/autoresearch" managedSkillEntries
      || throw "autoresearch skill not discovered from its flake input";
    assert
      builtins.elem ".agents/skills/premium-agent-orchestration" managedSkillEntries
      || throw "premium-agent-orchestration skill not discovered from the direct plugin input";
    assert
      builtins.elem ".agents/skills/browser-use" managedSkillEntries
      || throw "browser-use skill not discovered from the enabled Browser Use plugin";
    assert
      builtins.elem ".agents/skills/why" managedSkillEntries
      || throw "why skill not discovered from the context-engineering-kit input";
    assert
      builtins.elem ".agents/skills/kaizen" managedSkillEntries
      || throw "kaizen skill not discovered from the context-engineering-kit input";
    assert
      builtins.elem ".agents/skills/managing-dependencies" managedSkillEntries
      || throw "managing-dependencies skill not discovered from its flake input";
    assert
      builtins.elem ".agents/skills/file-organizer" managedSkillEntries
      || throw "file-organizer skill not deployed from programs.agentSkills.local";
    # The INDEX is what the loader-less harnesses (Copilot, cecli) actually read,
    # so a flat rebuild there is a silent regression for them specifically.
    assert
      builtins.match ".*\n## [^\n]+\n.*" indexText != null
      || throw "Agent Skills INDEX.md has no category headings";
    helpers.mkMarker "check-agent-skills-home-files" "Agent Skills home.file wiring: ${toString (builtins.length managedSkillEntries)} managed skill entries";
}
