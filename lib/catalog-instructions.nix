{ ai-llm-prompts, pkgs }:
ai-llm-prompts.packages.${pkgs.stdenv.hostPlatform.system}.instructions
