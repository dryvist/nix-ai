# nix-ai - AI Agent Instructions

AI CLI ecosystem for Claude, Gemini, Copilot, MCP servers via Nix home-manager modules.

## Critical Constraints

1. **Flakes-only**: Never use `nix-env` or imperative Nix commands
2. **Module args injection**: All flake inputs reach modules via `_module.args`, not function parameters
3. **Worktrees required**: Run `/refresh-repo` then create a worktree before any work
4. **No direct main commits**: Always use feature branches

## Validation

**Static** (every change):

```bash
nix flake check    # Formatting, statix, deadnix, regression tests
nix fmt            # Fix formatting
```

**Runtime** (changes to plugins, hooks, settings, activations, MCP servers):

```bash
sudo darwin-rebuild switch --flake "$HOME/git/nix-darwin/main" \
  --override-input nix-ai "$HOME/git/nix-ai/<worktree>"
```

Then verify in a live Claude Code session — static checks validate Nix
evaluation, not runtime behavior. Start a fresh session and confirm the
feature loads without errors before claiming done.

## Architecture

This repo exports home-manager modules consumed by nix-darwin:

- `homeManagerModules.default` — Full AI stack
- `homeManagerModules.claude` — Claude Code only
- `homeManagerModules.maestro` — Maestro orchestration only
- `lib.ci.claudeSettingsJson` — Pure JSON for CI validation

### Self-contained design

Modules inject their own dependencies via `_module.args`. Consumers only need:

```nix
inputs.nix-ai.inputs.nixpkgs.follows = "nixpkgs";
inputs.nix-ai.inputs.home-manager.follows = "home-manager";
```

## Separation Guidelines

### What belongs here (nix-ai)

- AI CLI tools (Claude Code, Gemini, Copilot, Codex, block-goose)
- MCP servers and wrappers (github-mcp-server, terraform-mcp-server, doppler-mcp, etc.)
- AI-specific GitHub CLI extensions (gh-aw)
- AI tool configuration files (`.claude/`, `.gemini/`, `.copilot/`)
- MLX inference server (vllm-mlx LaunchAgent + wrappers)
- AI-specific shell utilities (sync-mlx-models, hf CLI wrapper)

### Package placement

The `nix-package-placement` rule lives in
[ai-assistant-instructions/agentsmd/rules/nix-package-placement.md](https://github.com/JacobPEvans/ai-assistant-instructions/blob/main/agentsmd/rules/nix-package-placement.md)
and auto-loads via path-scoping when `.nix` / `flake.*` files are in context.
It contains the full decision matrix for the nix repos, including homebrew
constraints and on-demand patterns.

## Architecture Documentation

Cross-cutting views live in [`docs/architecture/`](docs/architecture/README.md):
system-integration-map (topology + ports), model-discovery-flow, config-lifecycle,
secrets-and-injection, mlx-stack. Design decisions in [`docs/adr/`](docs/adr/README.md).

## Key Files

- `modules/default.nix` — Module entry point
- `modules/claude/` — Claude Code module ([README](modules/claude/README.md))
- `modules/mcp/` — MCP server definitions
- `modules/mlx/` — MLX inference server (vllm-mlx LaunchAgent, CLI tools)
- `modules/common/` — Shared permission engine and formatters
- `lib/claude-settings.nix` — Pure settings generator (CI-only; deployment uses `modules/claude/settings.nix`)
- `lib/claude-registry.nix` — Marketplace format functions
- `lib/checks/` — Per-domain regression tests (lint, claude, mlx)

## MLX Ecosystem

Three tools — `parakeet-mlx` (audio), `mlx-vlm` (vision), `vllm-mlx` (LLM) — installed
as `uvx` wrappers; vllm-mlx runs as a LaunchAgent fronted by llama-swap. Full dependency
graph, version management, and operational notes (tool-call parser, idle eviction, MoE
throughput) in [`docs/architecture/mlx-stack.md`](docs/architecture/mlx-stack.md).
Port allocation lives in [`docs/architecture/system-integration-map.md`](docs/architecture/system-integration-map.md).

## Related Repos

This repo exports home-manager modules consumed by [`nix-darwin`](https://github.com/JacobPEvans/nix-darwin).
Sibling repos: [`nix-home`](https://github.com/JacobPEvans/nix-home) (user dev environment) and
[`nix-devenv`](https://github.com/JacobPEvans/nix-devenv) (reusable dev shells).
