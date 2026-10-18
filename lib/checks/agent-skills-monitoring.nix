# Monitoring-first checks for generated harness instructions and skill delivery.
{
  pkgs,
  hmConfig,
  instructions,
}:
let
  inherit (pkgs) lib;
  home = hmConfig.config.home;
  homeDir = home.homeDirectory;
  cfg = hmConfig.config.programs.agentSkills;
  homeFileNames = builtins.attrNames home.file;
  harnesses = import ../../modules/agent-skills/harnesses.nix;
  sharedInstructionLinks = builtins.attrValues harnesses.agentsMd;
  sharedAgentsMd = home.file.".agents/AGENTS.md".source;
  codexAgentsMd = home.file.".codex/AGENTS.md".source;
  sharedInstruction = import ../shared-agent-instructions.nix {
    inherit pkgs instructions;
  };
  countOccurrences = needle: text: builtins.length (lib.splitString needle text) - 1;
  geminiGlobalContext = home.file.".gemini/GEMINI.md".text;
  skillIndex = home.file.".codex/skills/INDEX.md".text;
  skillDir = cfg.deployedSkillPaths.".codex/skills/monitoring-first";
in
{
  agent-skills-monitoring-first =
    assert builtins.elem ".gemini/GEMINI.md" sharedInstructionLinks;
    assert builtins.elem ".zcode/AGENTS.md" sharedInstructionLinks;
    assert builtins.elem ".gemini/skills" homeFileNames;
    assert builtins.elem ".zcode/skills" homeFileNames;
    assert toString sharedAgentsMd == toString sharedInstruction;
    assert toString codexAgentsMd == toString sharedInstruction;
    assert countOccurrences "@${homeDir}/.agents/AGENTS.md" geminiGlobalContext == 1;
    assert !(lib.hasInfix "@${homeDir}/.agents/agentsmd/rules/operating-core.md" geminiGlobalContext);
    assert lib.hasInfix "@${homeDir}/.gemini/GEMINI.local.md" geminiGlobalContext;
    assert lib.hasInfix "- monitoring-first" skillIndex;
    assert builtins.pathExists "${skillDir}/SKILL.md";
    pkgs.runCommand "check-agent-skills-monitoring-first" { } ''
      rule_count=$(grep -Fc 'Check system state with monitoring first;' \
        "${instructions.pkg}/agentsmd/rules/operating-core.md" || true)
      if [ "$rule_count" -ne 1 ]; then
        echo "expected exactly one monitoring-first line in operating-core.md, found $rule_count" >&2
        exit 1
      fi
      delivered_count=$(grep -Fc 'Check system state with monitoring first;' "${sharedInstruction}" || true)
      if [ "$delivered_count" -ne 1 ]; then
        echo "expected exactly one monitoring-first line in shared AGENTS.md, found $delivered_count" >&2
        exit 1
      fi
      touch "$out"
    '';
}
