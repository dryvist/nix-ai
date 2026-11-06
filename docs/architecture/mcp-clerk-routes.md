---
type: Configuration
title: MCP clerk write routes
description: Optional clerk endpoints and runtime identity mappings for shared harness callers.
tags: [mcp, agentgateway]
timestamp: 2026-11-06T00:00:00Z
---

## Configuration

`programs.aiMcp.clerkRoutes.vikunja-clerk` and
`programs.aiMcp.clerkRoutes.zammad-clerk` default to `null`. Each accepts `url`
and `env_http_headers`: the complete published agentgateway MCP endpoint and a
mapping of identity header names to runtime environment variable names. Both
fields are required when a route is configured. Header mappings must be nonempty.
The configuration contains variable names only.

Configured clerks appear by agent name in the shared harness MCP profiles.
Claude uses a per-connection header helper, Codex and OpenCode use native
environment mappings, and Antigravity CLI/IDE and Qwen use the existing MCP bridge.
The `vikunja` and `zammad` read configurations retain their existing definitions.

Consumers supply endpoint publication and gateway grants separately. ZCode's
sandbox MCP configuration is managed outside this module; its grants permit
public reads and only task or comment writes through `vikunja-clerk` within its
own project. These options configure callers; gateway policy enforces resource
and operation scope.

See the [MCP configuration reference](../../modules/mcp/README.md) for shared
profiles and transports.
