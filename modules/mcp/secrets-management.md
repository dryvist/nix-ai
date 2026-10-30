# Secrets Management

The MCP config stores **no secrets** — it only references commands and URLs.
Servers that need API keys read them from environment variables at runtime.
Gateway caller keys follow the same rule: the config holds only the variable
name (`GATEWAY_KEY_<CALLER_ID>`, see Shared agentgateway routes). Each launcher
provides only its own variable. Delivering the value is the host's job and is
out of scope for this module.

**Inject secrets directly into each run — never write them to disk.**

- A server that needs credentials names them in `env_vars`. The consumer may
  set `programs.aiMcp.servers.<name>.launchPrefix`, an argv list prepended to
  the server's command (`<launchPrefix...> <command> <args>`), to supply them.
  `programs.aiMcp.launchPrefixFor`, a function from `env_vars` to that argv,
  sets it once for every stdio server with `env_vars`; a server's own
  `launchPrefix` still wins. This repo holds no secret-manager code; the
  prefix lives with the consumer.
  With no prefix, the server reads `env_vars` from the agent's own environment.
- Non-secret config (log levels, flags) belongs in the Nix-managed `env`
  attribute. Package-backed active servers use a 300-second startup and tool
  timeout so first-run `uvx`/`bunx` installs can complete before the MCP
  handshake deadline.
- Splunk is a gateway route (see [Shared agentgateway
  routes](README.md#shared-agentgateway-routes)): the client sends `SPLUNK_MCP_TOKEN`
  (a Splunk-minted `mcp_token`) as a bearer header, and the gateway passes it
  straight through to the Splunk backend. No OpenBao credential is involved.
- Env-var-backed servers (HF_TOKEN, GitHub PAT, UniFi, …) read from the process
  environment, injected directly or through a `launchPrefix`.

The full variable catalog — required vs optional and purpose — is
[`.env.example`](../../.env.example). Design rationale and full per-secret
runbooks live on the [docs site](https://docs.jacobpevans.com/security/overview)
and the private docs repo.

## Plugin-managed servers (context7)

Some servers are also provided by Claude Code plugins, which manage their own
MCP server lifecycle under a different name. The catalog's `context7` gateway
route and the plugin's own MCP coexist without conflict because they render as
distinct server names to Claude (`context7` vs
`mcp__plugin_context7_context7`); OpenCode and Codex have no plugin
and get `context7` only from the catalog route.

| Plugin | Server |
|--------|--------|
| `context7@claude-plugins-official` | context7 |
