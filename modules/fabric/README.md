# Fabric Module

Daniel Miessler's [Fabric](https://github.com/danielmiessler/fabric) — a Go CLI
providing 252+ reusable AI prompt patterns — packaged as a Nix home-manager
module for the nix-ai ecosystem.

## What it manages

This module owns the entire fabric runtime on a host:

- The `fabric` Go binary (built from source via `buildGoModule`, pinned to a
  release tag, Renovate-managed via the annotation in `package.nix`)
- The 252-pattern library symlinked read-only from the `fabric-src` flake input
  to `~/.config/fabric/patterns/`
- A user-managed custom patterns directory at
  `~/.config/fabric/custom-patterns/` (created on activation, exported as
  `FABRIC_CUSTOM_PATTERNS_DIR`)
- The `yt-dlp` package for YouTube/multimedia content extraction (added in
  `modules/ai-tools.nix`)
- An optional macOS LaunchAgent that runs `fabric --serve` on port 8180 (opt-in
  via `programs.fabric.enableServer`)
- Session variables (`FABRIC_PATTERNS_DIR`, `FABRIC_DEFAULT_MODEL`,
  `FABRIC_CUSTOM_PATTERNS_DIR`) for the user shell

What it does NOT manage:

- `~/.config/fabric/.env` (per-host secrets, set via `fabric --setup`)
- AI provider API keys (deferred to a future Doppler-injection PR — see #445)
- The fabric MCP server enablement state (defined in `programs.aiMcp.servers.fabric`)

## What this gives you

| Capability | How |
| --- | --- |
| `fabric` CLI on PATH | `home.packages` (built from source via `buildGoModule`) |
| 252 patterns at `~/.config/fabric/patterns/` | Nix-managed read-only symlink |
| User-managed custom patterns directory | `programs.fabric.customPatternsDir` (default `~/.config/fabric/custom-patterns`) |
| YouTube/multimedia extraction | `yt-dlp` added to `home.packages` |
| Optional REST API server (LaunchAgent) | `programs.fabric.enableServer = true` (port 8180) |
| 32 curated patterns as Claude Code skills | Synthetic marketplace at `modules/claude/marketplace-overrides.nix` |
| Fabric MCP server in Claude Code | `modules/mcp/catalog.nix` (community-maintained) |

## One-time runtime setup

Fabric reads provider credentials from `~/.config/fabric/.env`. Run setup once per host:

```bash
fabric --setup
```

Walk through the prompts. For local-only routing through MLX:

- `OPENAI_BASE_URL=http://127.0.0.1:11434/v1`
- `DEFAULT_MODEL=ollama/<your-mlx-model-id>`
- Skip the cloud provider keys (or wire them via Doppler — see #445)

The `~/.config/fabric/.env` file is intentionally NOT managed by Nix because it contains
secrets. The fabric module symlinks the read-only patterns directory but leaves provider
credentials to per-host setup.

## Module options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enable` | bool | `false` | Master enable flag (set to `true` in `modules/default.nix`) |
| `enableServer` | bool | `false` | Run `fabric --serve` as a macOS LaunchAgent on port 8180 |
| `host` | str | `"127.0.0.1"` | REST API server host |
| `port` | port | `8180` | REST API server port |
| `defaultModel` | str | `"mlx-community/Qwen3.5-122B-A10B-4bit"` | Default model for `fabric --pattern X` |
| `customPatternsDir` | str or null | `~/.config/fabric/custom-patterns` | User-managed custom patterns directory |

The read-only Nix-managed patterns directory always lives at
`~/.config/fabric/patterns/` and is exported via `FABRIC_PATTERNS_DIR`. It
is intentionally NOT a configurable option — the home-manager symlink key
and the env var must stay in sync, and making this user-overridable would
let them diverge silently. Custom patterns belong in `customPatternsDir`.

## Adding a custom pattern

Drop a directory under `customPatternsDir` matching the upstream layout:

```bash
mkdir -p ~/.config/fabric/custom-patterns/my_pattern
cat > ~/.config/fabric/custom-patterns/my_pattern/system.md <<'EOF'
# IDENTITY and PURPOSE
You are a custom pattern that <does something useful>.

# OUTPUT INSTRUCTIONS
- Output as markdown
- Be concise
EOF

fabric -l | grep my_pattern   # verify discovery
echo "test input" | fabric --pattern my_pattern
```

To disable custom pattern support entirely, set `programs.fabric.customPatternsDir = null;`
in your home-manager config.

## Common workflows

### YouTube → wisdom extraction

```bash
fabric -y "https://www.youtube.com/watch?v=VIDEO_ID" --pattern extract_wisdom
```

### Git diff → conventional commit message

```bash
git diff --staged | fabric --pattern create_git_diff_commit
```

### Article → improved writing

```bash
cat draft.md | fabric --pattern improve_writing > polished.md
```

### Code → review

```bash
cat src/main.go | fabric --pattern review_code
```

### Web URL → clean summary

```bash
fabric -u "https://example.com/article" --pattern summarize
```

## Integration with Claude Code

Two paths exist:

### Path A: As Claude Code skills (always-on, auto-discovery)

The synthetic marketplace at `modules/claude/marketplace-overrides.nix` wraps 32 curated
fabric patterns as Claude Code skills via `modules/claude/fabric-curated-patterns.json`.
Claude Code auto-loads them based on description matching when relevant to the user's task.

To add or remove curated patterns: edit the JSON file. The
`fabric-marketplace-build` regression check in `lib/checks/fabric.nix` will assert that
the SKILL.md count matches the JSON entry count after the next `nix flake check`.

### Path B: As MCP tools (explicit invocation)

The `fabric` MCP server in `modules/mcp/catalog.nix` exposes patterns as MCP tools using
[ksylvan/fabric-mcp](https://github.com/ksylvan/fabric-mcp) via uvx. This is a
**community-maintained** package (not official danielmiessler) — if it becomes
unmaintained, an alternative MCP wrapper will be needed.

## Version bumps

The fabric version is pinned in two places that MUST stay in sync:

1. `flake.nix` input pin: `url = "github:danielmiessler/fabric/v1.4.444";`
2. `modules/fabric/package.nix` version constant: `version = "1.4.444";`

The marketplace metadata version is derived from `package.nix` at Nix eval time —
no separate sync needed. Renovate manages bumps via the `# managed by: renovate`
annotation in `package.nix`. The CI guard `scripts/check-fabric-version-sync.sh`
asserts both stay in sync.

To bump manually: edit both values to the new version, run `nix build .#fabric-ai`,
copy the new `vendorHash` from the error message, paste it into `package.nix`, and re-build.

See #454 for the verification status of the Renovate configuration.

## Troubleshooting

### `fabric: error loading .env file`

Run `fabric --setup` once per host to create `~/.config/fabric/.env`. The file is
intentionally not managed by Nix because it contains credentials.

### `fabric --pattern X` returns nothing or hangs

Check that the MLX server is running: `launchctl list | grep vllm-mlx`. The default
model points at the local MLX endpoint at `http://127.0.0.1:11434/v1`. Verify with
`curl http://127.0.0.1:11434/v1/models`.

### Custom pattern not discovered by `fabric -l`

Verify `FABRIC_CUSTOM_PATTERNS_DIR` is set in your shell: `echo $FABRIC_CUSTOM_PATTERNS_DIR`.
If unset, you may need to start a new shell after `darwin-rebuild switch`. The directory
is created on activation but the env var only loads in fresh shells.

### Port 8180 conflict (when `enableServer = true`)

Check `lsof -i :8180`. Override with `programs.fabric.port = <other_port>` in your
host config. The port allocation table in the repo's top-level `CLAUDE.md` lists which
ports are reserved by other services.

### Marketplace SKILL.md count mismatch in `nix flake check`

The `fabric-marketplace-build` check failed because the curated JSON
(`modules/claude/fabric-curated-patterns.json`) was edited but the synthetic marketplace
wasn't rebuilt. Just re-run `nix flake check` — the regression test recomputes the
expected count from the JSON.

## See also

- Upstream: <https://github.com/danielmiessler/fabric>
- Pattern library: <https://github.com/danielmiessler/fabric/tree/main/data/patterns>
- Curated subset: `modules/claude/fabric-curated-patterns.json`
- Regression tests: `lib/checks/fabric.nix`
- Follow-up issues: #442 (enable MCP), #443 (this README + completions), #444 (regression tests),
  #445 (auth + Doppler), #446 (expand patterns), #447 (nix-devenv), #451 (SecLists),
  #452 (decision tree docs), #453 (orchestrator cleanup), #454 (Renovate verification),
  #455 (LaunchAgent enable on macbook-m4)
