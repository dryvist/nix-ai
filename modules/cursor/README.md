# Cursor CLI Module

This module manages the Cursor terminal coding agent (`agent` / `cursor-agent`)
as a Nix derivation. The Cursor IDE itself is installed separately via
nix-darwin (`home.packages = [ code-cursor ]`).

## Installation

Enable the module in your home-manager configuration:

```nix
{ nix-ai, ... }: {
  imports = [ nix-ai.homeManagerModules.cursor ];

  programs.cursor.enable = true;
}
```

The module is included by default in `nix-ai.homeManagerModules.default`.

## Usage

Once enabled, the following are available on PATH after `darwin-rebuild switch`:

- `agent` — the Cursor terminal agent command
- `cursor-agent` — the same binary under its canonical name

The `code-cursor` IDE wrapper (`cursor agent`) will execute the Nix-owned
binary via the `~/.local/bin/cursor-agent` symlink.

Configuration is managed through:

- `programs.cursor.approvalMode` — `"allowlist"` (default) or `"bypass"`
- `programs.cursor.vimMode` — enable vim keybindings in the CLI
- `programs.cursor.excludedMcpServers` — list of MCP server names to exclude
- `programs.cursor.extraSettings` — additional keys merged into `cli-config.json`

MCP servers are configured via the shared catalog (`programs.aiMcp.enabledServers`)
and rendered to `~/.cursor/mcp.json` declaratively.

## Ownership Model

**Nix owns the CLI.** After every rebuild/activation:

1. **Profile install** — `home.packages = [ cursorCliPkg ]` puts the lab-pinned
   `cursor-agent` binary on PATH via the Nix profile.
2. **`~/.local/bin` links** — The `code-cursor` IDE wrapper and the upstream
   installer contract both require `agent` and `cursor-agent` at
   `~/.local/bin/`. The `cursorAgentReclaim` activation hook re-creates both
   symlinks on every activation, pointing at the store binary.
3. **Self-updater counter-measure** — Cursor's self-updater rewrites these
   names at runtime between activations. `cursorAgentReclaim` runs after
   `linkGeneration` (which removes empty parent dirs) to re-assert Nix
   ownership.

**What Nix does NOT manage:**

- `~/.local/bin/cursor` — the self-updater's third name; inert for our two
  owned commands.
- `~/.local/share/cursor-agent/versions/` — version directories created by the
  self-updater; do not affect the Nix-owned `agent` / `cursor-agent` names.
- `~/.config/cursor/agent` — self-updater config directory.
- `.cursor/mcp.json` — managed declaratively via `home.file` (unchanged).
- `cli-config.json` — deep-merged on activation via `cursorConfigMerge`
  (unchanged).
- `herdr` server, `normalizeMcpServer`, `mcpServers`, `cursorConfigMerge` —
  all unchanged.

## Bump Procedure

The lab channel uses a date+short-hash scheme (e.g., `2026.09.02-c22c1a3`)
with **no datasource** — the installer page is the only discovery mechanism.
No Renovate annotation is used (same exception as `omoSenpi`).

1. **Discover the latest lab version:**

   ```bash
   curl -s https://cursor.com/install | grep -oE 'lab/[^/]+' | head -1
   # Output: lab/2026.09.02-c22c1a3
   ```

2. **Update the pin in `lib/versions.nix`:**

   ```nix
   cursorCli = "2026.09.02-c22c1a3";
   ```

3. **Fetch the two pinned checksums:**

   ```bash
   # x86_64-linux
   nix store prefetch-file --json \
     "https://downloads.cursor.com/lab/2026.09.02-c22c1a3/linux/x64/agent-cli-package.tar.gz"

   # aarch64-darwin
   nix store prefetch-file --json \
     "https://downloads.cursor.com/lab/2026.09.02-c22c1a3/darwin/arm64/agent-cli-package.tar.gz"
   ```

4. **Put the hashes in `modules/cursor/package.nix`** (replace the
   `lib.fakeHash` placeholders).

5. **Verify:**

   ```bash
   nix build '.#cursor-cli'                    # darwin (local)
   nix build '.#checks.x86_64-linux.cursor-cli-build'  # linux (CI)
   nix flake check                             # full eval + all checks
   ```

## Out of Scope

- **IDE packaging** — `code-cursor` is managed by nix-darwin, not this module.
- **MCP servers** — `.cursor/mcp.json` is declarative `home.file`; the shared
  catalog renders it.
- **CLI config merge** — `cursorConfigMerge` deep-merges Nix defaults over
  runtime state; unchanged.
- **herdr** — separate module, not touched.
- **Other agent modules** — opencode, antigravity, codex, cecli, qwen-code
  are unaffected.
- **No cron/updater** — bump is manual per the procedure above.
- **No secrets** — no API keys, no `curl | bash`.
- **No `sudo darwin-rebuild` prerequisite** — the sandbox check (`cursor-reclaim-sandbox`)
  proves the reclaim logic without a live rebuild. A `darwin-rebuild switch`
  is an optional, permission-gated smoke test only.
