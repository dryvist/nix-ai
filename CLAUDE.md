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
nix fmt            # Fix formatting
nix flake check    # Packages, formatters, devShells

# Regression suite (lib/checks/) — REQUIRED on macOS, see below
nix eval --raw .#checks.x86_64-linux \
  --apply 'cs: builtins.concatStringsSep "\n" (map (c: c.outPath) (builtins.attrValues cs))' \
  >/dev/null
```

**A bare `nix flake check` on a Mac runs none of `lib/checks/`.** `checks` is
scoped to `x86_64-linux` (flake.nix), so on aarch64-darwin it omits them, prints
green for packages and formatters, and says nothing about the regression suite.
A module argument `launchd.nix` required and `default.nix` never passed survived
a green bare check and failed only at `darwin-rebuild`.

`--all-systems` surfaces the assertions but then tries to *build* Linux
derivations on darwin, exiting non-zero for that unrelated reason — so it cannot
be routine. The `nix eval` form above forces every check's `outPath`: every
assertion runs at evaluation time, nothing builds. Verified both ways — passes
on a healthy tree, fails on a deliberately broken one.

**Workaround; PR #1819 is the structural fix.** It builds `checks` for every
supported system, so a plain `nix flake check` runs the darwin assertions.
When it lands, replace the `nix eval` form above — noting `--all-systems` on a
Linux-only runner then tries to realise the darwin markers and fails.

Assertions only fire when something forces them, so a check that reads a few
attributes of a large structure proves nothing about the rest. Where a check
covers a nested tree (the launchd agents, for one) it should `deepSeq` it.

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
- `homeManagerModules.{claude,herdr,maestro}` — subsets
- `nixosModules.herdr` — herdr server (only non-darwin output)
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

- AI CLI tools (Claude Code, Antigravity, Codex, Copilot, Cursor, qwen-code, cecli)
- MCP servers and wrappers (github-mcp-server, terraform-mcp-server, doppler-mcp, etc.)
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

- `modules/default.nix` — Entry point
- `modules/claude-config.nix` — Claude Code config (schema/renderer from `nix-claude-code`)
- `modules/claude/plugins/` — Plugin tiers ([README](modules/claude/plugins/README.md))
- `modules/mcp/catalog.nix` — MCP server definitions
- `modules/herdr/` — herdr ([README](modules/herdr/README.md))
- `modules/mlx/` — MLX inference server (LaunchAgent, CLI tools)
- `modules/common/` — Permission engine and formatters
- `vars/ai-stack.nix` — Model/endpoint/version registry
- `lib/checks/` — Per-domain regression tests (lint, claude, mlx, herdr)

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
