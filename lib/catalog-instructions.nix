{ ai-llm-prompts, pkgs }:
{
  src = ai-llm-prompts + "/auto-ai-agent/instructions";
  pkg = ai-llm-prompts.packages.${pkgs.stdenv.hostPlatform.system}.instructions;
}
