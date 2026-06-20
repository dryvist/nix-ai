# MCP Servers - Nix-Native Configuration

MCP server definitions are owned by the `modules/mcp` Home Manager module. The
shared catalog lives in `catalog.nix` and is exposed as `programs.aiMcp.servers`.
Claude, Codex, and Gemini consume that option and render it into their own
configuration formats during every `darwin-rebuild switch`.

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

## Enabling / Disabling Servers

All servers are enabled by default (`disabled = false` is the module system
default). To disable a server, set `disabled = true`:

```nix
programs.aiMcp.servers.postgresql.disabled = true;
```

To enable a disabled server without editing `catalog.nix`, override via the
module system. Because the catalog uses plain assignments (priority 100), the
override must use `lib.mkForce` to win the merge:

```nix
programs.aiMcp.servers.postgresql.disabled = lib.mkForce false;
```

## Secrets Management

### Environment variables (default)

Servers requiring API keys read them from environment variables at runtime.
Use your secrets manager (Doppler, Keychain, 1Password, etc.) to inject env vars.

Required env vars are documented in comments above each server definition.
The config does NOT store any secrets — it only references commands and URLs.

### macOS Keychain injection (PAT, HF_TOKEN, etc.)

For tokens that are not in Doppler, the established pattern in nix-darwin injects them
from the macOS Keychain via `_get_keychain_secret` in the shell init:

```bash
# In nix-darwin hosts/macbook-m4/home.nix:
export HF_TOKEN=${HF_TOKEN:-"$(_get_keychain_secret 'HF_TOKEN' 'ai-cli-coder')"}
```

The account name (`ai-cli-coder`) and keychain db (`automation.keychain-db`) are defined
in `lib/user-config.nix` in nix-darwin. Adapt these values if your setup uses different names.

The shell exports the env var, and AI clients plus their MCP servers inherit it
at startup. Secrets are never written to generated client config or any
Nix-managed file.

**One-time setup:** Add secrets to macOS Keychain:

```bash
security add-generic-password -U -s HF_TOKEN -a "ai-cli-coder" -w "your-token-here" automation.keychain-db
```

### Doppler injection via `doppler-mcp`

For servers whose secrets live in Doppler (project `ai-ci-automation`, config `prd`),
set `command = "doppler-mcp"` and shift the original command into `args[0]`:

```nix
google-workspace = {
  command = "doppler-mcp";
  args = [ "uvx" "--from" "google-workspace-mcp" "workspace-mcp" ];
  env = {
    LOG_LEVEL = "INFO";    # non-secret config → Nix
    # GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET → injected by Doppler at runtime
  };
};
```

The `doppler-mcp` script (defined in `ai-tools.nix`) runs:

```bash
doppler run -p ai-ci-automation -c prd -- <original-command> [args...]
```

Secrets are fetched at subprocess launch time and injected as environment variables.
They are never written to `~/.claude.json` or any other file Claude Code can read.

**Non-secret config belongs in `env`, not Doppler.** Values like feature flags, timeouts,
and log levels are not sensitive and belong in the Nix-managed `env` attribute.

### Plugin-managed servers (context7)

Some servers are provided by Claude Code plugins and manage their own MCP server lifecycle.
Do **not** define these in `mcp/catalog.nix` — doing so creates a duplicate that causes
conflicts on startup.

| Plugin | Server |
|--------|--------|
| `context7@claude-plugins-official` | context7 |

## HuggingFace MCP

The `huggingface` server provides tools for searching and exploring HuggingFace Hub.

**Requires:** `HF_TOKEN` env var injected from macOS Keychain (see Secrets Management above).

**One-time Keychain setup:**

```bash
security add-generic-password -U -s HF_TOKEN -a "ai-cli-coder" -w "your-hf-token-here" automation.keychain-db
```

**Available tools:** search models, datasets, spaces, and papers; get model/dataset info; compare models.

## UniFi Network MCP

The `unifi` server ([enuno/unifi-mcp-server](https://github.com/enuno/unifi-mcp-server),
installed via `uvx`) manages a local UniFi gateway/controller. It is **local-only** —
it talks to the gateway on the LAN, so it only works on a machine with network access
to that gateway.

`UNIFI_API_TYPE` is pinned to `local` in the catalog. The remaining variables are
inherited from the shell environment (inject via macOS Keychain, same pattern as
`HF_TOKEN`):

| Variable | Purpose |
|----------|---------|
| `UNIFI_API_KEY` | API key from unifi.ui.com (secret) |
| `UNIFI_LOCAL_HOST` | Gateway IP, e.g. `192.168.1.1` (machine-specific) |

**One-time Keychain setup (secret):**

```bash
security add-generic-password -U -s UNIFI_API_KEY -a "ai-cli-coder" -w "your-key-here" automation.keychain-db
```

Then export both in the nix-darwin shell init (the gateway IP is not secret):

```bash
export UNIFI_API_KEY=${UNIFI_API_KEY:-"$(_get_keychain_secret 'UNIFI_API_KEY' 'ai-cli-coder')"}
export UNIFI_LOCAL_HOST="192.168.1.1"
```

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

2. New servers are enabled by default. Add `// { disabled = true; }` to start disabled.

3. Run `darwin-rebuild switch --flake .` to deploy.

4. Verify: `cat ~/.claude.json | jq .mcpServers`

## Troubleshooting

### Server not appearing in Claude Code

1. Check `disabled` is not set to `true` in `programs.aiMcp.servers`
2. Run `darwin-rebuild switch --flake .`
3. Restart Claude Code
4. Check `~/.claude.json` contains the server: `jq .mcpServers ~/.claude.json`

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
