# MCP Servers - Nix-Native Configuration

MCP server definitions are owned by the `modules/mcp` Home Manager module. The
shared catalog lives in `catalog.nix` and is exposed as `programs.aiMcp.servers`.
The default cross-agent profile is `programs.aiMcp.enabledServers`. Claude,
Codex, Antigravity, and Qwen consume that one option and render it into their
own configuration formats during every `darwin-rebuild switch`.

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

# Python package via uvx
huggingface = {
  command = "uvx";
  args = [ "huggingface-mcp-server" ];
};
```

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

## Global Profile / Per-Agent Exclusions

The catalog is intentionally wider than the default profile. Servers stay out of
the cross-agent profile when either:

- `programs.aiMcp.servers.<name>.disabled = true`
- `<name>` is listed in `programs.aiMcp.excludedServers`

To disable a server everywhere, prefer the shared profile:

```nix
programs.aiMcp.excludedServers = [ "postgresql" ];
```

To keep a server in the shared profile but omit it from one renderer, use that
agent's `excludedMcpServers` option:

```nix
programs.codex.excludedMcpServers = [ "postgresql" ];
programs.antigravity-cli.excludedMcpServers = [ "postgresql" ];
programs.antigravity-ide.excludedMcpServers = [ "postgresql" ];
programs.qwen-code.excludedMcpServers = [ "postgresql" ];
```

Use per-agent exclusions only for client incompatibility. Routine policy belongs
in `programs.aiMcp.excludedServers` so Claude, Codex, Antigravity, Qwen, and
future clients stay aligned.

To enable a catalog-disabled server without editing `catalog.nix`, override via
the module system. Because the catalog uses plain assignments (priority 100),
the override must use `lib.mkForce` to win the merge:

```nix
programs.aiMcp.servers.postgresql.disabled = lib.mkForce false;
```

## Secrets Management

The MCP config stores **no secrets** — it only references commands and URLs.
Servers that need API keys read them from environment variables at runtime.

**Inject secrets directly into each run — never write them to disk.** Use your
secrets manager per command:

- Doppler-backed servers (Google Workspace, Splunk) use the `doppler-mcp` wrapper,
  which runs `doppler run -p ai-ci-automation -c prd -- <cmd>` at launch (see
  [Adding New Servers](#adding-new-servers)). Non-secret config (log levels,
  flags) belongs in the Nix-managed `env` attribute, not Doppler.
- Env-var-backed servers (HF_TOKEN, GitHub PAT, UniFi, …) read from the process
  environment, injected directly (e.g. an inline Keychain read or `doppler run`).

The full variable catalog — required vs optional, purpose, and source manager —
is [`.env.example`](../../.env.example). The local injection runbook (the
direct-injection commands and which manager holds what) is `AGENTS.local.md`
(gitignored). Design rationale:
[`docs/architecture/secrets-and-injection.md`](../../docs/architecture/secrets-and-injection.md).
Full per-secret runbooks live in the `dryvist/docs` site and `docs-starlight`.

### Plugin-managed servers (context7)

Some servers are provided by Claude Code plugins and manage their own MCP server lifecycle.
Do **not** define these in `mcp/catalog.nix` — doing so creates a duplicate that causes
conflicts on startup.

| Plugin | Server |
|--------|--------|
| `context7@claude-plugins-official` | context7 |

## HuggingFace MCP

The `huggingface` server provides tools for searching and exploring HuggingFace Hub.

**Requires:** `HF_TOKEN` (see [Secrets Management](#secrets-management) and
[`.env.example`](../../.env.example)) — inject it directly at runtime.

**Available tools:** search models, datasets, spaces, and papers; get model/dataset info; compare models.

## UniFi Network MCP

The `unifi` server ([enuno/unifi-mcp-server](https://github.com/enuno/unifi-mcp-server),
installed via `uvx`) manages a local UniFi gateway/controller. It is **local-only** —
it talks to the gateway on the LAN, so it only works on a machine with network access
to that gateway.

`UNIFI_API_TYPE` is pinned to `local` in the catalog. The rest are injected
directly at runtime from your secrets manager (see [`.env.example`](../../.env.example)
and `AGENTS.local.md`):

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

Authentication is **browser OAuth handled by the MCP client** on first connect: the
client opens Monarch in the browser to authorize access. No token, password, or header
is stored in the Nix config — there is nothing to put in Doppler or Keychain.

## MLX Inference (Local Apple Silicon)

Two CLI tools work together for local MLX model workflows:

| Tool | Purpose |
|------|---------|
| `hf` | Download and manage models from HuggingFace Hub |
| `vllm-mlx` | Serve MLX models as OpenAI/Anthropic-compatible API |

**Typical workflow:**

```bash
# 1. Search for a model via HuggingFace MCP in Claude Code
# 2. Download it (uses the default model from modules/mlx/options.nix)
hf download "$MLX_DEFAULT_MODEL"

# 3. Serve it locally (OpenAI-compatible endpoint at :8000)
vllm-mlx serve "$MLX_DEFAULT_MODEL"
```

Both tools are `uvx` wrappers defined in `ai-tools.nix` — no separate installation needed.

## Adding New Servers

1. Choose the transport:
   - Local stdio process → inline attribute set with `command` (and optionally `args`)
   - Local stdio with Doppler secrets → set `command = "doppler-mcp"`, shift original command to `args[0]`
   - Local stdio env var from Keychain → set env var in nix-darwin shell init, server inherits it
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

### doppler-mcp server shows "Failed to connect"

**Root cause (diagnosed 2026-03-25):** Claude Code launches all MCP servers in parallel at
session startup. The `doppler-mcp` wrapper previously ran a synchronous preflight check
(`doppler run ... -- true`) before the actual MCP server could start. This Doppler API
round-trip — fetching secrets just to run `true` — delayed the MCP server's stdio handshake
past Claude Code's connection timeout. The preflight also doubled startup time by fetching
secrets twice (once for check, once for real command).

**Fix:** The preflight was removed from `doppler-mcp` (in `modules/ai-tools.nix`).
The wrapper now goes straight to `exec doppler run ... -- "$@"`. Auth failures are handled
natively by `doppler run` (exits non-zero with a clear error message).

**If you still see failures after the fix:**

1. Verify Doppler auth: `doppler me`
2. Test the wrapper manually: `doppler-mcp <server-command>` (Ctrl-C to stop)
3. Check the invocation log: `cat ~/.local/state/doppler-mcp.log`
   - Records commands only, not error details
   - Doppler auth errors go to stderr — re-run the logged command in a terminal to see them
4. If Doppler auth expired: `doppler login`, then restart Claude Code
5. Verify registration: `claude mcp list | grep "^<server>:"`

**Mid-session recovery** (if a server failed at startup but Doppler is now healthy):

```bash
claude mcp remove <server> -s user && claude mcp add <server> -s user -- <command>
```

This reconnects the server, but tools won't appear in the current session's ToolSearch.
Restart Claude Code for full tool availability.
