# Monitoring-first checks for generated harness instructions and skill delivery.
{
  pkgs,
  hmConfig,
  ai-assistant-instructions,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  home = hmConfig.config.home;
  homeDir = home.homeDirectory;
  cfg = hmConfig.config.programs.agentSkills;
  homeFileNames = builtins.attrNames home.file;
  harnesses = import ../../modules/agent-skills/harnesses.nix;
  sharedInstructionLinks = builtins.attrValues harnesses.agentsMd;
  operatingCore = builtins.readFile "${ai-assistant-instructions}/agentsmd/rules/operating-core.md";
  monitoringRules = builtins.filter (line: lib.hasInfix "monitoring-first" line) (
    lib.splitString "\n" operatingCore
  );
  countOccurrences = needle: text: builtins.length (lib.splitString needle text) - 1;
  geminiGlobalContext = home.file.".gemini/GEMINI.md".text;
  sharedAgentsMd = home.file.".agents/AGENTS.md".text;
  codexContext = hmConfig.config.programs.codex.context;
  skillIndex = home.file.".codex/skills/INDEX.md".text;
  skillDir = cfg.deployedSkillPaths.".codex/skills/monitoring-first";
in
{
  agent-skills-monitoring-first =
    assert builtins.length monitoringRules == 1;
    assert builtins.elem ".gemini/GEMINI.md" sharedInstructionLinks;
    assert builtins.elem ".zcode/AGENTS.md" sharedInstructionLinks;
    assert builtins.elem ".gemini/skills" homeFileNames;
    assert builtins.elem ".zcode/skills" homeFileNames;
    assert countOccurrences (builtins.head monitoringRules) sharedAgentsMd == 1;
    assert countOccurrences (builtins.head monitoringRules) codexContext == 1;
    assert countOccurrences "@${homeDir}/.agents/AGENTS.md" geminiGlobalContext == 1;
    assert !(lib.hasInfix "@${homeDir}/.agents/agentsmd/rules/operating-core.md" geminiGlobalContext);
    assert lib.hasInfix "@${homeDir}/.gemini/GEMINI.local.md" geminiGlobalContext;
    assert lib.hasInfix "- monitoring-first" skillIndex;
    assert builtins.pathExists "${skillDir}/SKILL.md";
    helpers.mkMarker "check-agent-skills-monitoring-first" "Generated monitoring-first harness context and skill delivery";
}
