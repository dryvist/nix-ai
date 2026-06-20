# GitHub Copilot Instructions — nix-ai

## Repository Purpose

nix-ai is an AI CLI ecosystem (Claude Code, Antigravity, Codex, Copilot, MCP
servers, MLX inference) delivered as Nix home-manager modules. It exports
modules consumed by `nix-darwin`; this repo holds the module definitions, not a
deployed system.

## Critical Constraints

- **Flakes-only.** Never generate `nix-env` or other imperative Nix commands.
- **Module args injection.** Flake inputs reach modules via `_module.args`, not
  function parameters.
- **No direct main commits.** Always work on a feature branch in a worktree.

## Validation

Static checks run on every change:

```bash
nix flake check    # formatting, statix, deadnix, regression tests
nix fmt            # auto-fix formatting
```

Runtime changes (plugins, hooks, settings, activations, MCP servers) also need a
real rebuild and a fresh Claude Code session — static checks validate Nix
evaluation, not runtime behavior:

```bash
sudo darwin-rebuild switch --flake "$HOME/git/nix-darwin/main" \
  --override-input nix-ai "$HOME/git/nix-ai/<worktree>"
```

## Conventions

- Scripts longer than a few lines live in `scripts/*.sh`, never inline in `.nix`.
- Never hardcode model IDs, endpoints, or version strings — read them from
  `vars/ai-stack.nix` (the central registry).
- Never put secrets in Nix expressions or `env:` blocks; they end up in the
  world-readable Nix store. Use Doppler or the macOS Keychain.

## Key Files

- `modules/default.nix` — module entry point
- `modules/mcp/catalog.nix` — shared MCP server catalog
- `modules/mlx/` — local Apple Silicon inference (vllm-mlx LaunchAgent)
- `vars/ai-stack.nix` — model/endpoint/version registry
- `lib/checks/` — per-domain regression tests

See [`CLAUDE.md`](../CLAUDE.md) and [`docs/architecture/`](../docs/architecture/README.md)
for the full architecture.
