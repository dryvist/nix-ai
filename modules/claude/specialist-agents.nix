# Claude Code subagent files for the specialists in lib/specialists.nix whose
# owned MCP servers are all enabled. Each file carries its owned servers in
# frontmatter; no shared profile does.
{
  lib,
  pkgs,
  ai-llm-prompts,
  specialistMcpServers,
}:
let
  render = import ../../lib/specialist-agent.nix { inherit lib pkgs ai-llm-prompts; };
  active = lib.filter (s: lib.all (n: builtins.hasAttr n specialistMcpServers) s.owns) (
    import ../../lib/specialists.nix
  );
in
map (s: {
  inherit (s) name;
  source =
    (render (
      s
      // {
        mcpServers = lib.filterAttrs (n: _: lib.elem n s.owns) specialistMcpServers;
      }
    )).markdown;
}) active
