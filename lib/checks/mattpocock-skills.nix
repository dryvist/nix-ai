{
  pkgs,
  src,
  hmConfig,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.agentSkills;
  skills = builtins.filter (
    skill:
    lib.hasInfix "/skills/engineering/" (toString skill.source)
    || lib.hasInfix "/skills/productivity/" (toString skill.source)
  ) cfg.fromFlakeInputs;
  first = builtins.head skills;
  upstream = builtins.dirOf (builtins.dirOf (builtins.dirOf (builtins.dirOf first.source)));
  manifest = lib.importJSON "${upstream}/.claude-plugin/plugin.json";
  names = map (skill: skill.name) skills;
  manualNames = map (skill: skill.name) (builtins.filter (skill: skill.userInvoked) skills);
  modelNames = lib.subtractLists manualNames names;
  hidden = import ../../modules/agent-skills/discovery.nix {
    inherit lib pkgs;
    marketplaceInputs.mattpocock = upstream;
    enabledPlugins."mattpocock-skills@mattpocock" = false;
  };
  grouped = mkHmConfig [
    {
      programs = {
        agentSkills = {
          root = "agents";
          activeGroups = [ "productivity" ];
        };
        ai.untrustedClis.enable = true;
        opencode.configDir = ".config/opencode-test";
      };
    }
  ];
  deployed = cfg.deployedSkillPaths;
  groupedNames = builtins.attrNames grouped.config.programs.agentSkills.deployedSkillPaths;
  productivity = cfg.categories.productivity;
  keepListed = import ../../modules/claude/always-listed-skills.nix;
in
{
  mattpocock-skills =
    assert builtins.length skills == 27;
    assert builtins.length manualNames == 16 && builtins.length modelNames == 11;
    assert builtins.length names == builtins.length (lib.unique names);
    assert builtins.length manifest.skills == builtins.length names;
    assert builtins.all (
      skill: deployed.".codex/skills/${skill.name}" == builtins.dirOf skill.source
    ) skills;
    assert builtins.all (
      skill:
      builtins.pathExists "${deployed.".codex/skills/${skill.name}"}/agents/openai.yaml"
      &&
        (lib.hasInfix "allow_implicit_invocation: false" (
          builtins.readFile "${deployed.".codex/skills/${skill.name}"}/agents/openai.yaml"
        )) == skill.userInvoked
    ) skills;
    assert builtins.pathExists "${deployed.".codex/skills/tdd"}/tests.md";
    assert builtins.pathExists "${deployed.".codex/skills/teach"}/MISSION-FORMAT.md";
    assert builtins.length (builtins.filter (skill: skill.name == "handoff") cfg.fromFlakeInputs) == 1;
    assert hidden == [ ];
    assert builtins.all (name: lib.elem name keepListed) modelNames;
    assert builtins.all (name: !(lib.elem name keepListed)) manualNames;
    assert builtins.all (name: lib.elem ".agents/skills/${name}" groupedNames) productivity;
    assert !(lib.elem ".agents/skills/tdd" groupedNames);
    assert lib.hasInfix "grill-me (user-invoked only)"
      hmConfig.config.home.file.".codex/skills/INDEX.md".text;
    pkgs.runCommand "check-mattpocock-skills"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.gawk
        ];
        KEEP_LISTED = lib.concatStringsSep " " keepListed;
        SKILL_PATHS = lib.concatStringsSep " " manifest.skills;
        MANUAL_NAMES = lib.concatStringsSep " " manualNames;
        MODEL_NAMES = lib.concatStringsSep " " modelNames;
        PRODUCTIVITY_MANUAL_NAMES = lib.concatStringsSep " " (lib.intersectLists productivity manualNames);
      }
      ''
        ${pkgs.bash}/bin/bash ${src}/scripts/check-mattpocock-skills.sh ${upstream} \
          ${hmConfig.config.home.file.".config/opencode/opencode.json".source} \
          ${grouped.config.home.file.".config/opencode-test/opencode.json".source} \
          ${src}/modules/claude/scripts
        touch $out
      '';
}
