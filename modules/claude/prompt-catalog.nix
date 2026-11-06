# Subagents and always-loaded rules delivered from the ai-llm-prompts catalog.
# Split out of claude-config.nix to keep that file under the org file-size limit.
# Each catalog directory holds an OKF index.md, which is not a delivered file.
{
  lib,
  pkgs,
  ai-llm-prompts,
  discoverMarkdownFiles,
  mkSourceEntries,
  specialistMcpServers,
}:
let
  root = "${ai-llm-prompts}/auto-ai-agent/claude-code";
  entries =
    dir: mkSourceEntries "${root}/${dir}" (lib.remove "index" (discoverMarkdownFiles "${root}/${dir}"));
in
{
  # Plus the specialists in lib/specialists.nix.
  agents =
    entries "agents"
    ++ import ./specialist-agents.nix {
      inherit
        lib
        pkgs
        ai-llm-prompts
        specialistMcpServers
        ;
    };
  rules = entries "rules";
}
