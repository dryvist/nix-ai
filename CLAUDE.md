# nix-ai - AI Agent Instructions

AI CLI ecosystem for Claude, Antigravity, Codex, Copilot, and MCP servers via
Nix home-manager modules.

## Critical Constraints

1. **Flakes-only**: Never use `nix-env` or imperative Nix commands
2. **Module args injection**: All flake inputs reach modules via `_module.args`, not function parameters
3. **Worktrees required**: Start a worktree with `git town hack` before any work
4. **No direct main commits**: Always use feature branches

## Validation

Run the formatter and native checks for each change:

```bash
nix fmt
nix flake check
nix flake check --no-build --all-systems
```

The native check builds the current system's exported checks. Darwin runs its
focused checks; the full regression suite is exported for x86_64-linux and
must be built on a Linux runner. The all-system command evaluates checks for
both systems without building their derivations. CI also runs a Darwin lane.

Assertions only fire when something forces them, so a check that reads a few
attributes of a large structure proves nothing about the rest. Where a check
covers a nested tree (the launchd agents, for one) it should `deepSeq` it.

For changes to plugins, hooks, settings, activations, or MCP servers, follow
the consuming host's documented deployment procedure and host guards. Verify
the affected behavior in a fresh harness session before claiming runtime
success; static checks do not establish live behavior.

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
the `ai-llm-prompts` catalog's `instructions` package. It delivers the always-on
core (`soul.md`) plus the
path-scoped tier rules flat to `~/.claude/rules/`; Claude Code's native loader
then honors each file's `paths:` frontmatter (present = path-scoped, absent =
always-on). The `on-demand/` tier is a subdir that discovery skips by design —
read by path when needed, never delivered. The one sanctioned fallback for a
non-Nix machine is cloning the `ai-llm-prompts` catalog and reading
`auto-ai-agent/instructions/AGENTS.md` + `auto-ai-agent/instructions/agentsmd/rules/`
(the source tree exported by its `instructions` package). The
CI-sparse-checkout, Obsidian-submodule, and copy-paste "pipes" are not sync
mechanisms and do not exist — do not add a second delivery path.

### nix-ai vs nix-claude-code boundary

`nix-claude-code` = the Claude Code option schema, settings/permission renderer,
permission data, and marketplace catalog (the "what the config looks like").
`nix-ai` = discovery, consumption, MCP, plugin tiers, MLX, and the glue that
feeds the catalog's `instructions` package content through nix-claude-code's options (the
"what content flows and how"). Tiered rule delivery (top-level delivered,
`on-demand/` not) is a property of nix-ai's `discoverMarkdownFiles`, using
nix-claude-code's `rules` option verbatim. Mirror in
[nix-claude-code `AGENTS.md`](https://github.com/JacobPEvans/nix-claude-code/blob/main/AGENTS.md).

### Test ownership follows the same boundary

A regression test that proves one of nix-claude-code's own declared
defaults holds — "X stays null/absent unless a consumer overrides it," "the
runtime merge doesn't resurrect a stale value" — belongs in nix-claude-code's
own test suite, not here. `lib/checks/claude.nix` should only assert values
nix-ai itself deliberately sets. Testing "we correctly did not override
this" duplicates a guarantee that is nix-claude-code's to keep, and only
nix-claude-code's own suite can prove it holds for every consumer, not just
this one.

### What belongs here (nix-ai)

- AI CLI tools (Claude Code, Antigravity, Codex, Copilot, qwen-code, cecli)
- MCP servers and wrappers (github-mcp-server, terraform-mcp-server, etc.)
- AI tool configuration files (`.claude/`, `.gemini/`, `.copilot/`)
- MLX inference server (mlx_lm.server LaunchAgent + llama-swap + wrappers)
- AI-specific shell utilities (hf CLI wrapper, Doppler-wrapped aliases)

### Package placement

Package placement guidance is documented in
[`docs/architecture/per-agent-flakes.md`](docs/architecture/per-agent-flakes.md).

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
- `modules/mlx/` — MLX inference server (mlx_lm.server LaunchAgent, CLI tools)
- `modules/common/` — Shared permission engine and formatters
- `vars/ai-stack.nix` — Central model/endpoint/version registry
- `lib/checks/` — Per-domain regression tests (lint, claude, mlx)

## MLX Ecosystem

Three tools — `parakeet-mlx` (audio), `mlx-vlm` (vision), `mlx-lm` (LLM). The first two are
`uvx` wrappers; `mlx_lm.server` runs as a LaunchAgent fronted by llama-swap. Full dependency
graph, version management, and operational notes (tool-call parser, idle eviction, MoE
throughput) in [`docs/architecture/mlx-stack.md`](docs/architecture/mlx-stack.md).
Port allocation lives in [`docs/architecture/system-integration-map.md`](docs/architecture/system-integration-map.md).

## Related Repos

This repo exports home-manager modules consumed by [`nix-darwin`](https://github.com/JacobPEvans/nix-darwin).
Sibling repos: [`nix-home`](https://github.com/JacobPEvans/nix-home) (user dev environment) and
[`nix-devenv`](https://github.com/JacobPEvans/nix-devenv) (reusable dev shells).
