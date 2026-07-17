# nix-ai - AI Agent Instructions

AI CLI ecosystem for Claude, Antigravity, Codex, Copilot, and MCP servers via
Nix home-manager modules.

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

### Instruction delivery (single pipe)

home-manager is the single canonical delivery pipe for agent instructions from
`ai-assistant-instructions`. It delivers the always-on core (`soul.md`) plus the
path-scoped tier rules flat to `~/.claude/rules/`; Claude Code's native loader
then honors each file's `paths:` frontmatter (present = path-scoped, absent =
always-on). The `on-demand/` tier is a subdir that discovery skips by design —
read by path when needed, never delivered. The one sanctioned fallback for a
non-Nix machine is cloning `ai-assistant-instructions` and reading `AGENTS.md` +
`agentsmd/rules/` directly (as that repo's own CLAUDE.md instructs). The
CI-sparse-checkout, Obsidian-submodule, and copy-paste "pipes" are not sync
mechanisms and do not exist — do not add a second delivery path.

### nix-ai vs nix-claude-code boundary

`nix-claude-code` = the Claude Code option schema, settings/permission renderer,
permission data, and marketplace catalog (the "what the config looks like").
`nix-ai` = discovery, consumption, MCP, plugin tiers, MLX, and the glue that
feeds `ai-assistant-instructions` content through nix-claude-code's options (the
"what content flows and how"). Tiered rule delivery (top-level delivered,
`on-demand/` not) is a property of nix-ai's `discoverMarkdownFiles`, using
nix-claude-code's `rules` option verbatim. Mirror in
[nix-claude-code `AGENTS.md`](https://github.com/JacobPEvans/nix-claude-code/blob/main/AGENTS.md).

### What belongs here (nix-ai)

- AI CLI tools (Claude Code, Antigravity, Codex, Copilot, qwen-code, cecli)
- MCP servers and wrappers (github-mcp-server, terraform-mcp-server, doppler-mcp, etc.)
- AI-specific GitHub CLI extensions (gh-aw)
- AI tool configuration files (`.claude/`, `.gemini/`, `.copilot/`)
- MLX inference server (vllm-mlx LaunchAgent + wrappers)
- AI-specific shell utilities (hf CLI wrapper, Doppler-wrapped aliases)

### Package placement

The `nix-package-placement` rule lives in
[ai-assistant-instructions/agentsmd/rules/nix-package-placement.md](https://github.com/JacobPEvans/ai-assistant-instructions/blob/main/agentsmd/rules/nix-package-placement.md)
and auto-loads via path-scoping when `.nix` / `flake.*` files are in context.
It contains the full decision matrix for the nix repos, including homebrew
constraints and on-demand patterns.

## Architecture Documentation

Cross-cutting views live in [`docs/architecture/`](docs/architecture/README.md):
system-integration-map (topology + ports), config-lifecycle, mlx-stack. Secrets
injection patterns live on the [docs site](https://docs.jacobpevans.com/security/overview)
instead. Design decisions in [`docs/adr/`](docs/adr/README.md).

## Key Files

- `modules/default.nix` — Module entry point
- `modules/claude-config.nix` — Claude Code config (settings/permissions/marketplace catalog come from the `nix-claude-code` flake input)
- `modules/claude/plugins/` — Plugin tier files ([README](modules/claude/plugins/README.md))
- `modules/mcp/catalog.nix` — MCP server definitions
- `modules/mlx/` — MLX inference server (vllm-mlx LaunchAgent, CLI tools)
- `modules/common/` — Shared permission engine and formatters
- `vars/ai-stack.nix` — Central model/endpoint/version registry
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
