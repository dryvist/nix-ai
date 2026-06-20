# Architecture Documentation

This directory contains cross-cutting architecture views for nix-ai's AI tool ecosystem.

## Relationship to Other Docs

| Document | Audience | Covers |
|----------|----------|--------|
| `CLAUDE.md` (repo root) | Developers | **How to develop** in this repo — critical constraints, validation commands, key files, module separation rules |
| `modules/mcp/README.md` | MCP users | **Per-module reference** — MCP transports, secrets, troubleshooting |
| `docs/ai-tool-decision-tree.md` | Users | **When to use what** — Fabric vs Bifrost |
| `docs/architecture/` (here) | Architects, AI assistants | **How the system works** — integration topology, data flows, design decisions |
| `docs/adr/` | Decision-makers | **Why things are the way they are** — architectural decision records |

## Documents in This Directory

### [system-integration-map.md](system-integration-map.md)

Full integration diagram showing all 10 AI products and how they connect. Start here for
an overview of what talks to what, which ports are used, and which MCP servers are shared
across tools vs product-specific.

**Read when**: Understanding the overall topology, debugging why a tool cannot reach another,
adding a new AI product.

### [config-lifecycle.md](config-lifecycle.md)

The 3-phase config generation pipeline unique to Nix home-manager: build-time pure evaluation,
activation-time shell scripts (which can query live APIs), and runtime CLI tools for
inter-rebuild refreshes. Explains which config files are managed by which phase and why.

**Read when**: Adding a new config file, debugging why a setting change does not take effect
after `darwin-rebuild switch`, or understanding which config files refresh between rebuilds.

### [secrets-and-injection.md](secrets-and-injection.md)

The three distinct secrets injection patterns: Doppler subprocess wrappers, macOS Keychain
via shell init, and Kubernetes Doppler Operator for in-cluster services. Maps which products
use which pattern and explains the trust boundary each pattern enforces.

**Read when**: Adding a new MCP server that needs API keys, debugging secrets not reaching
a subprocess, or auditing where credentials flow.

### [mlx-stack.md](mlx-stack.md)

The three user-facing MLX tools (parakeet-mlx, mlx-vlm, vllm-mlx) and their shared library
dependencies. Includes the dependency graph, version management strategy, and operational
notes covering tool-call parser compatibility, idle eviction, and MoE vs dense throughput.

**Read when**: Adding a new MLX tool, debugging a model loading or tool-calling issue,
or understanding why the 35B model is preloaded vs the 122B MoE.

### [per-agent-flakes.md](per-agent-flakes.md)

The uniform module layout each AI agent module follows (`default.nix`, `options.nix`,
`packages.nix`, `settings.nix`, `README.md`), the install-source preference rule
(nixpkgs → local Nix derivation → brew), the contract for sharing brew formulae with
nix-darwin, and the recipe for graduating an in-tree agent module to its own standalone
flake. Reference implementations: `modules/cecli/` (`buildPythonApplication`) and
`modules/qwen-code/` (brew). Includes a "Why not uv2nix" trade-off analysis.

**Read when**: Adding a new AI agent CLI to nix-ai, refactoring one of the existing
modules (Claude/Gemini/Codex/fabric) to the uniform layout, or extracting a module
into a standalone flake.

### [plugin-scoping.md](plugin-scoping.md)

The two-layer model partitioning Claude Code plugins between user-level (every session)
and per-repo (only inside specific worktrees). Covers the skill listing budget, the
`enabledPlugins` deep-merge mechanism, and the mapping of project-specific plugins to
consumer repos.

**Read when**: `/doctor` reports "skill descriptions dropped", adding a new plugin to nix-ai,
or enabling a project-specific plugin in a consumer repo.

## ADRs

[`docs/adr/`](../adr/README.md) contains the decisions behind non-obvious design choices.
If you find yourself wondering "why does it work this way?", the ADR index is the place to look.

## Runbooks

[`docs/runbooks/`](../runbooks/) contains operational guides for non-obvious workflows:

| Runbook | Purpose |
|---------|---------|
| [galileo-onboarding.md](../runbooks/galileo-onboarding.md) | Galileo AI observability setup, daily use, denylist management, and kill switches |
