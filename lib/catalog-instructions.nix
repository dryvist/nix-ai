{ ai-llm-prompts, pkgs }:
{
  # src: plain source tree, safe to list and probe during evaluation (names only,
  # its Markdown still carries catalog frontmatter). pkg: rendered tree, built, never read at evaluation.
  src = ai-llm-prompts + "/auto-ai-agent/instructions";
  pkg = ai-llm-prompts.packages.${pkgs.stdenv.hostPlatform.system}.instructions;
}
