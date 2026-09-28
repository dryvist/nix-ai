# On-demand MCP servers

MCP tool schemas are the largest addressable per-session cost (measurements in
[agent-context-architecture.md](agent-context-architecture.md)), so every local
server is held out of the always-on profile unless nearly every session calls it.

`programs.aiMcp.onDemandServers` holds servers out of the always-on profile and
renders each to `~/.claude/mcp-available/<name>.json`, so a session that needs
one attaches it explicitly:

```sh
claude --mcp-config ~/.claude/mcp-available/zammad.json
```

A repository attaches on-demand servers through its skill groups: the linker
unions `GROUP-MCP.json` entries for the declared groups (default `homelab` →
zammad; `ai` → fabric, grep, time, token-meter) with any AGENTS.md
`mcp-servers:` list, and rebuilds the managed part of `.mcp.json` from
`~/.claude/mcp-available/`. Servers it does not manage stay in the file.
`enabledMcpjsonServers` lists every on-demand name, so no approval prompt fires.

The curated list is a config-level definition, so a host appending a name keeps
it (`lib/checks/mcp.nix` -> `mcp-on-demand-merge`); as an option default it was
replaced by any consumer definition and silently returned every server to the
always-on profile.

`lib/checks/mcp.nix` -> `shared-mcp-on-demand-reachable` asserts both halves:
an on-demand server must be absent from the always-on profile **and** present as
an attachable file. Absent from both is a silent capability loss, which is the
failure mode this tier is most likely to produce.

`ENABLE_TOOL_SEARCH` is pinned to `true` by nix-claude-code, the documented
always-defer value, rather than an `auto:N` threshold.
