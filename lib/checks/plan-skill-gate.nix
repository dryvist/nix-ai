# Runs the rendered ExitPlanMode hook against transcripts with and without the
# agentops plan skill, so the gate is proven by behavior, not by its text.
{ pkgs, hmConfig }:
let
  gated = hmConfig.extendModules {
    modules = [ { programs.agentHooks.planSkillGate.enable = true; } ];
  };
  entries = builtins.filter (entry: (entry.matcher or "") == "ExitPlanMode") (
    gated.config.programs.claude.hooks.events.PreToolUse or [ ]
  );
  hook = pkgs.writeShellScript "plan-skill-gate" (builtins.head (builtins.head entries).hooks)
  .command;
in
{
  plan-skill-gate =
    assert builtins.length entries == 1 || throw "expected one ExitPlanMode PreToolUse entry";
    pkgs.runCommand "check-plan-skill-gate" { } ''
      set -u
      run() { printf '{"transcript_path":"%s"}' "$1" | ${hook}; }
      printf '%s\n' '{"type":"user","message":{"content":"plan this"}}' > none.jsonl
      printf '%s\n' '{"type":"tool_use","name":"Skill","input":{"skill":"agentops:plan"}}' > skill.jsonl
      printf '%s\n' '{"type":"user","message":{"role":"user","content":"<command-name>/agentops:plan</command-name>"}}' > slash.jsonl
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"\"skill\":\"agentops:plan\" \"content\":\"<command-name>/agentops:plan<"}]}}' > mention.jsonl
      run "$PWD/none.jsonl" 2>/dev/null
      [ $? -eq 2 ] || { echo "ExitPlanMode was allowed without the plan skill" >&2; exit 1; }
      run "$PWD/mention.jsonl" 2>/dev/null
      [ $? -eq 2 ] || { echo "ExitPlanMode was allowed by a mere mention of the plan skill" >&2; exit 1; }
      run "$PWD/skill.jsonl" || { echo "ExitPlanMode was blocked after the Skill call" >&2; exit 1; }
      run "$PWD/slash.jsonl" || { echo "ExitPlanMode was blocked after /agentops:plan" >&2; exit 1; }
      touch "$out"
    '';
}
