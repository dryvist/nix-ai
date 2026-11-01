# MCP Servers - Nix-Native Configuration

`modules/mcp` owns MCP definitions. `catalog.nix` exposes
`programs.aiMcp.servers`; Claude, Codex, Antigravity, and Qwen render the shared
`programs.aiMcp.enabledServers` profile on rebuild.

Standalone consumers import `modules/mcp/module.nix` for the shared catalog and
required local wrappers.

**Nix is the sole manager of user-scoped MCP servers.** Any entries added manually
through client CLIs may be overwritten on the next rebuild.

## Transports

### stdio (local processes)

Run a local command as the MCP server. Use the `official` helper for Anthropic servers,
or write inline attribute sets for custom servers:

```nix
# Official Anthropic server via bunx
fetch = official "fetch";

# nixpkgs binary (resolved via PATH)
github = { command = "github-mcp-server"; };

# Python package (Nix derivation)
huggingface = {
  command = "${mcpPkgs.huggingface-mcp-server}/bin/huggingface-mcp-server";
  args = [ ];
};
```

Python servers are Nix derivations in [`packages.nix`](packages.nix). Never
`uvx` — a live uvx process holds a uv-cache lock that blocks all pruning.

### SSE / HTTP (remote servers)

Connect to a running HTTP server using SSE or HTTP transport:

```nix
# SSE server
cribl = {
  type = "sse";
  url = "http://localhost:30030/mcp";
};

# HTTP server with custom headers
my-server = {
  type = "http";
  url = "http://localhost:8080/mcp";
  headers = { Authorization = "Bearer \${TOKEN}"; };
};
```

### Shared agentgateway routes

`context7`, `splunk`, `docs`, and `memory` are `gatewayRoute` entries in
`catalog.nix`: one governed URL per capability on shared agentgateway, rather
than a local process per harness. They ship **disabled** because this public
repo has no default for the private gateway URL. Set
`programs.aiMcp.gatewayBaseUrl` (e.g. with `lib.mkForce` in a private host
module) to enable them for every renderer. `splunk` also needs
`SPLUNK_MCP_TOKEN` (a Splunk-minted `mcp_token`); the gateway forwards the
caller's `Authorization` header unchanged.

## Facade canary

`programs.aiMcp.facadeCanary = true` keeps its legacy meaning: `agent-facade` is
the only server for every shared client. It takes precedence over the per-client
selectors below. Evaluation fails if the consumer defines or enables another
server, or leaves `gatewayBaseUrl` unset.

`programs.aiMcp.facadeCanaryClients` has one default-off boolean for each shared
client: `claude`, `codex`, `antigravity-cli`, `antigravity-ide`, `qwen-code`, and
`opencode`. Setting one to `true` makes that client's entire regular, on-demand,
and skill-group MCP set the canonical `/agents` `agent-facade` route; every
unselected client's rendered MCP sets stay unchanged. The unknown `antigravity-ide`
header transport is not verified, so setting its selector fails evaluation.
Selecting Claude also clears Claude's `GROUP-MCP` attachments. Selecting another
client leaves those Claude-only attachments alone.

Claude's selected `/agents` facade resolves the registered `claude-code` caller
ID to `GATEWAY_KEY_CLAUDE_CODE` in its per-connection `headersHelper`. A host
may opt into `programs.aiMcp.gatewayKeyLaunchPrefixFor` to run a configured
prefix when that key is missing. The other supported facade renderers continue
using `AGENT_FACADE_KEY`: Codex uses `env_http_headers`, OpenCode uses its
`{env:AGENT_FACADE_KEY}` syntax, and Antigravity CLI/Qwen Code use the
`mcp-remote` bridge. These Nix assertions prove rendered configuration only;
caller credentials and backend permissions still require the separate live
cutover receipt before a host enables a selector.

Non-canary consumers are checked against the hand-edited
[`facade-baseline.nix`](facade-baseline.nix). Entries are only removed, never added.
Workspace and project `.mcp.json` files and Hermes are covered by separate checks
outside this repository.

## Global Profile / Per-Agent Exclusions

The catalog is wider than the default profile. Servers are excluded when:

- `programs.aiMcp.servers.<name>.disabled = true`
- `<name>` is listed in `programs.aiMcp.excludedServers`
- the server is platform-specific and incompatible with the current host
  (`apple-events` is Darwin-only)

To disable a server everywhere, prefer the shared profile:

```nix
programs.aiMcp.excludedServers = [ "postgresql" ];
```

To omit a shared server from one renderer, use its `excludedMcpServers` option:

```nix
programs.codex.excludedMcpServers = [ "postgresql" ];
programs.antigravity-cli.excludedMcpServers = [ "postgresql" ];
programs.antigravity-ide.excludedMcpServers = [ "postgresql" ];
programs.qwen-code.excludedMcpServers = [ "postgresql" ];
```

Use per-agent exclusions for client incompatibility; use
`programs.aiMcp.excludedServers` for shared policy.

To enable a catalog-disabled server, use `lib.mkForce` to override the
catalog's plain assignments (priority 100):

```nix
programs.aiMcp.servers.postgresql.disabled = lib.mkForce false;
```

## Secrets Management

MCP config stores **no secrets**; it references commands and URLs. Servers read
API keys from their runtime environment.

**Inject secrets directly into each run — never write them to disk.**

- Servers name credentials in `env_vars`. Consumers supply them through a
  per-server `launchPrefix` argv (`<prefix...> <command> <args>`) or shared
  `programs.aiMcp.launchPrefixFor`, a function from `env_vars` to argv. A
  server's own prefix wins. This repo has no secret-manager code; prefixes live
  with consumers. Without a prefix, the agent environment supplies `env_vars`.
- Put non-secret config (log levels, flags) in Nix-managed `env`. Package-backed
  active servers use 300-second startup/tool timeouts for first-run
  `uvx`/`bunx` installs.
- Splunk is a gateway route (see [Shared agentgateway
  routes](#shared-agentgateway-routes)): the client sends `SPLUNK_MCP_TOKEN`
  (a Splunk-minted `mcp_token`) as a bearer header, and the gateway passes it
  straight through to the Splunk backend. No OpenBao credential is involved.
- Env-var-backed servers (HF_TOKEN, GitHub PAT, UniFi, …) read from the process
  environment, injected directly or through a `launchPrefix`.

The full variable catalog — required vs optional and purpose — is
[`.env.example`](../../.env.example). Design rationale and full per-secret
runbooks live on the [docs site](https://docs.jacobpevans.com/security/overview)
and the private docs repo.

### Plugin-managed servers (context7)

Plugins own their MCP servers. Claude's catalog and plugin `context7` coexist as
`context7` and `mcp__plugin_context7_context7`; OpenCode and Codex use the
catalog route.

| Plugin | Server |
|--------|--------|
| `context7@claude-plugins-official` | context7 |

## HuggingFace MCP

The `huggingface` server searches and explores HuggingFace Hub.

**Requires:** `HF_TOKEN` (see [`.env.example`](../../.env.example)).

**Tools:** search models, datasets, spaces, and papers; inspect models and datasets; compare models.

## UniFi Network MCP

The `unifi` server ([enuno/unifi-mcp-server](https://github.com/enuno/unifi-mcp-server),
installed via `uvx`) manages a local UniFi gateway/controller. It is **local-only** —
it talks to the gateway on the LAN, so it only works on a machine with network access
to that gateway.

`UNIFI_API_TYPE` is pinned to `local` in the catalog. The rest are read from
the environment (see [`.env.example`](../../.env.example)):

| Variable | Purpose |
|----------|---------|
| `UNIFI_API_KEY` | API key from unifi.ui.com (secret) |
| `UNIFI_LOCAL_HOST` | Gateway IP, e.g. `192.168.0.1` (real value is topology — keep it in the no-password secret store, never committed) |

`unifi` ships disabled; enabling it without these set makes the server fail to
start. Inject directly — do not write the key to disk.

## Monarch Money MCP

The `monarch` server is Monarch's official hosted connector — a remote
Streamable-HTTP endpoint at `https://api.monarch.com/mcp`
([setup guide](https://help.monarch.com/hc/en-us/articles/50207234679956-Monarch-MCP-Connector)).

On first connect, the MCP client opens Monarch for browser OAuth. Nix stores no
token, password, or header.

## OpenWhispr MCP and CLI

Hosted connector at `https://mcp.openwhispr.com/mcp` ([setup](https://docs.openwhispr.com/integrations/mcp)).
**Requires:** `OPENWHISPR_API_KEY` (see [`.env.example`](../../.env.example)). CLI: [`ai-tools.nix`](../ai-tools.nix).

## MLX Inference (Local Apple Silicon)

Two CLI tools work together for local MLX model workflows:

| Tool | Purpose |
|------|---------|
| `hf` | Download and manage models from HuggingFace Hub |
| `mlx_lm.server` | Serve MLX models as an OpenAI-compatible API (programs.mlx, behind llama-swap on :11434) |

**Typical workflow:**

```bash
# 1. Search for a model via HuggingFace MCP in Claude Code
# 2. Download it (uses the default model from modules/mlx/options.nix)
hf download "$MLX_DEFAULT_MODEL"

# 3. Query it through the local llama-swap proxy
curl http://127.0.0.1:11434/v1/models
```

`hf` is a `uvx` wrapper defined in `ai-tools.nix`; the server is the programs.mlx LaunchAgent.

## Adding New Servers

1. Choose the transport:
   - Local stdio process → inline attribute set with `command` (and optionally `args`)
   - Local stdio with credentials → list them in `env_vars`; the consumer's `launchPrefix` supplies them
   - Remote SSE/HTTP endpoint → inline attribute set with `type` and `url`
   - Plugin-managed → do NOT add here; let the plugin manage it

2. New servers are enabled by default unless `disabled = true` or listed in
   `programs.aiMcp.excludedServers`.

3. Run `darwin-rebuild switch --flake .` to deploy.

4. Verify rendered server names:

```bash
jq '.mcpServers | keys' ~/.claude.json
rg '^\[mcp_servers\.' ~/.codex/config.toml
jq '.mcpServers | keys' ~/.gemini/antigravity-cli/settings.json
jq '.mcpServers | keys' ~/.gemini/config/mcp_config.json
jq '.mcpServers | keys' ~/.qwen/settings.json
```

## Troubleshooting

### Server not appearing in an agent

1. Check it is in `programs.aiMcp.enabledServerNames`
2. Check it is not listed in that agent's `excludedMcpServers`
3. Run `darwin-rebuild switch --flake .`
4. Restart the agent
5. Check the rendered config contains the server

### SSE server shows connection error

Expected when the remote server is not running (e.g., OrbStack k8s is stopped).
The server definition is still deployed — it will connect when the server is available.

### "command not found" for a stdio server

Verify the binary is in PATH. For nixpkgs packages, ensure it's installed in your profile
or system packages. For bunx/uvx, ensure bun/uv is installed.

### A gateway route (splunk/docs/memory/context7) doesn't appear

Check `programs.aiMcp.gatewayBaseUrl` is set — the catalog entries ship
disabled without it. For `splunk` specifically, also confirm `SPLUNK_MCP_TOKEN`
is present in the harness's environment; an expired or missing token surfaces
as a connection failure from the gateway, not from this repo's Nix config.

### A credentialed server shows "Failed to connect"

Claude Code launches MCP servers in parallel at startup. A server behind
`launchPrefix` fails when the prefix cannot supply its `env_vars`. Run the
rendered command line by hand (`<launchPrefix...> <command>`) to see the
prefix's own error, then restart Claude Code. Mid-session:
`claude mcp remove <server> -s user && claude mcp add <server> -s user -- <command>`
(restart for full ToolSearch availability).
