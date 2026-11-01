# Specialist subagents (lib/specialists.nix). Each MCP server a specialist owns
# is loaded only by its owner, and every active specialist renders a Claude agent
# file plus a Codex role registered in config.toml.
{
  pkgs,
  hmConfig,
  hmConfigMcpLaunchPrefix,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  specialists = import ../specialists.nix;
  owned = lib.concatMap (s: s.owns) specialists;
  owning = lib.filter (s: s.owns != [ ]) specialists;
  on = hmConfigMcpLaunchPrefix.config;
  sharedSets = {
    enabledServers = on.programs.aiMcp.enabledServerNames;
    onDemandEnabledServers = builtins.attrNames on.programs.aiMcp.onDemandEnabledServers;
    claude = builtins.attrNames on.programs.claude.mcpServers;
    codex = on.programs.codex.mcpServerNames;
    antigravity-cli = on.programs.antigravity-cli.mcpServerNames;
    antigravity-ide = on.programs.antigravity-ide.mcpServerNames;
    qwen-code = on.programs.qwen-code.mcpServerNames;
    opencode = on.programs.opencode.mcpServerNames;
  };
  leakedInto = builtins.filter (set: lib.any (n: lib.elem n sharedSets.${set}) owned) (
    builtins.attrNames sharedSets
  );
  # Tools as lib/specialist-agent.nix renders them.
  toolsOf = s: s.tools or (map (n: "mcp__${n}__*") s.owns);
  claudeFile = s: ".claude/agents/${s.name}.md";
  codexFile = s: ".codex/agents/${s.name}.toml";

  claudeAgentCheck =
    s:
    lib.nameValuePair "specialist-claude-${s.name}" (
      pkgs.runCommand "check-specialist-claude-${s.name}" { } ''
        f=${on.home.file.${claudeFile s}.source}
        grep -qxF 'name: ${s.name}' "$f"
        ${lib.optionalString ((s.model or null) != null) ''grep -qxF 'model: ${s.model}' "$f"''}
        ${lib.concatMapStrings (t: "grep -qxF -- '- ${t}' \"$f\"\n") (toolsOf s)}
        ${
          if s.owns == [ ] then
            ''! grep -q '^mcpServers:' "$f"''
          else
            ''
              grep -qxF 'mcpServers:' "$f"
              ${lib.concatMapStrings (n: "grep -q '^  ${n}:' \"$f\"\n") s.owns}
            ''
        }
        ! grep -q 'type: LLM Prompt' "$f"
        touch $out
      ''
    );

  codexRoleCheck =
    s:
    lib.nameValuePair "specialist-codex-${s.name}" (
      pkgs.runCommand "check-specialist-codex-${s.name}" { } ''
        f=${on.home.file.${codexFile s}.source}
        grep -qxF 'name = "${s.name}"' "$f"
        grep -q '^developer_instructions = ' "$f"
        ! grep -q '^model = ' "$f"
        ${
          if s.owns == [ ] then
            ''! grep -q 'mcp_servers' "$f"''
          else
            lib.concatMapStrings (n: "grep -qxF '[mcp_servers.${n}]' \"$f\"\n") s.owns
        }
        touch $out
      ''
    );
in
{
  specialist-owners-unique =
    assert
      owned == lib.unique owned
      || throw "an MCP server is owned by more than one specialist: ${builtins.toJSON owned}";
    assert
      (lib.length (lib.unique (map (s: s.name) specialists)) == lib.length specialists)
      || throw "specialist names in lib/specialists.nix must be unique";
    helpers.mkMarker "check-specialist-owners-unique" "Each MCP server has one owning specialist and specialist names are unique";

  specialist-owned-servers-global-absent =
    assert
      leakedInto == [ ]
      || throw "specialist-owned MCP servers are rendered into shared sets: ${builtins.toJSON leakedInto}";
    assert
      lib.all (n: !(builtins.hasAttr ".claude/mcp-available/${n}.json" on.home.file)) owned
      || throw "a specialist-owned MCP server has an on-demand attach file";
    helpers.mkMarker "check-specialist-owned-servers-global-absent" "Specialist-owned MCP servers are absent from every shared harness MCP set and on-demand file";

  specialist-absent-when-disabled =
    assert
      lib.all (s: !(builtins.hasAttr (claudeFile s) hmConfig.config.home.file)) owning
      || throw "a specialist with an owned server rendered while that server is disabled";
    assert
      lib.all (s: !(builtins.hasAttr s.name hmConfig.config.programs.codex.generatedAgents)) owning
      || throw "a specialist with an owned server registered in Codex while that server is disabled";
    helpers.mkMarker "check-specialist-absent-when-disabled" "Specialists with owned servers do not render while those servers are disabled";

  specialist-codex-registration =
    assert
      lib.all (
        s: (on.programs.codex.generatedAgents.${s.name}.config_file or null) == "./agents/${s.name}.toml"
      ) specialists
      || throw "a specialist is missing its Codex config.toml registration: ${builtins.toJSON on.programs.codex.generatedAgents}";
    helpers.mkMarker "check-specialist-codex-registration" "Every specialist is registered in Codex config.toml";
}
// lib.listToAttrs (map claudeAgentCheck specialists)
// lib.listToAttrs (map codexRoleCheck specialists)
