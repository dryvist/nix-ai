# Codex roles for the specialists in lib/specialists.nix whose owned MCP servers
# are all enabled. A role carries its owned servers; the shared mcp_servers
# table that every role inherits never does. Each role is registered under
# [agents.<name>] in config.toml, resolved against ~/.codex.
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
  roleToml =
    s:
    let
      owned = lib.filterAttrs (n: _: lib.elem n s.owns) specialistMcpServers;
      role = {
        inherit (s) name description;
        developer_instructions = (render s).body;
      }
      // lib.optionalAttrs (owned != { }) { mcp_servers = owned; };
      json = pkgs.writeText "codex-${s.name}.json" (builtins.toJSON role);
    in
    pkgs.runCommand "codex-${s.name}.toml" { nativeBuildInputs = [ pkgs.yj ]; } ''
      yj -jt < ${json} > $out
    '';
in
{
  registration = lib.listToAttrs (
    map (s: lib.nameValuePair s.name { config_file = "./agents/${s.name}.toml"; }) active
  );
  files = lib.listToAttrs (
    map (s: lib.nameValuePair ".codex/agents/${s.name}.toml" { source = roleToml s; }) active
  );
}
