# Subagents and always-loaded rules delivered from the ai-llm-prompts catalog.
# Split out of claude-config.nix to keep that file under the org file-size limit.
# Each catalog directory holds an OKF index.md, which is not a delivered file.
{
  lib,
  ai-llm-prompts,
  discoverMarkdownFiles,
  mkSourceEntries,
}:
let
  root = "${ai-llm-prompts}/auto-ai-agent/claude-code";
  entries =
    dir: mkSourceEntries "${root}/${dir}" (lib.remove "index" (discoverMarkdownFiles "${root}/${dir}"));
in
{
  agents = entries "agents";
  rules = entries "rules";
}
