# One specialist subagent, rendered from its ai-llm-prompts source. Entries are
# listed in lib/specialists.nix.
#
# The prompt body is the source with its OKF frontmatter removed (the catalog's
# `render.frontmatter: strip` rule). Claude gets the body as a file behind YAML
# frontmatter; Codex embeds the same text as developer_instructions.
{
  lib,
  pkgs,
  ai-llm-prompts,
}:
spec:
let
  s = {
    model = null;
    owns = [ ];
    tools = null;
    mcpServers = { };
  }
  // spec;
  # Claude's tools allowlist: explicit when given, else every owned server's tools.
  tools = if s.tools != null then s.tools else map (n: "mcp__${n}__*") s.owns;
  text = builtins.readFile "${ai-llm-prompts}/${s.prompt}";
  parts = lib.splitString "\n---\n" text;
  body =
    assert lib.hasPrefix "---\n" text || throw "${s.prompt} has no OKF frontmatter to strip";
    lib.removePrefix "\n" (lib.concatStringsSep "\n---\n" (lib.tail parts));
  frontmatter = (pkgs.formats.yaml { }).generate "${s.name}-frontmatter.yaml" (
    {
      inherit (s) name description;
    }
    // lib.optionalAttrs (s.model != null) { inherit (s) model; }
    // lib.optionalAttrs (tools != [ ]) { inherit tools; }
    // lib.optionalAttrs (s.mcpServers != { }) { inherit (s) mcpServers; }
  );
  markdown = pkgs.runCommand "${s.name}.md" { } ''
    {
      echo ---
      cat ${frontmatter}
      echo ---
      echo
      cat ${pkgs.writeText "${s.name}-body.md" body}
    } > $out
  '';
in
{
  inherit body markdown;
}
