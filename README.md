# nix-ai

[![CI](https://github.com/dryvist/nix-ai/actions/workflows/ci-gate.yml/badge.svg)](https://github.com/dryvist/nix-ai/actions/workflows/ci-gate.yml)
[![Release](https://img.shields.io/github/v/release/dryvist/nix-ai?sort=semver)](https://github.com/dryvist/nix-ai/releases)
[![License](https://img.shields.io/github/license/dryvist/nix-ai)](LICENSE)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)

## Your AI coding toolkit, declared once. Reproduced everywhere

Ever spent hours configuring Claude Code plugins, Gemini settings, and MCP servers
— only to lose it all when you switch machines? **nix-ai** captures your entire AI
setup as code using [Nix](https://nixos.org/). One command rebuilds everything,
identically, every time.

---

## What it manages

| Tool | What you get |
| ---- | ------------ |
| **Claude Code** | [Plugin ecosystem](modules/claude/plugins/README.md), hooks, agents, commands, rules |
| **Gemini / Antigravity** | CLI + IDE settings, custom commands, permission rules |
| **GitHub Copilot** | Configuration, permissions |
| **OpenAI Codex** | Settings, rules, approval policy |
| **Qwen Code & Cecli** | Settings for the Alibaba and Aider-fork CLIs |
| **MCP Servers** | One [catalog](modules/mcp/README.md) (GitHub, Terraform, Context7, filesystem, memory, …) fanned out to every agent |
| **AI Dev Tools** | cclint, doppler-mcp, claude-flow, and more |
| **MLX** *(macOS)* | Local Apple Silicon inference via vllm-mlx with launchd integration |

## Prerequisites

- [Nix](https://nixos.org/) with flakes (Determinate Nix recommended)
- [home-manager](https://github.com/nix-community/home-manager)
- A supported platform: `aarch64-darwin` or `x86_64-linux`

## Installation

Add the input to your flake:

```nix
{
  inputs.nix-ai = {
    url = "github:dryvist/nix-ai";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
  };
}
```

Then add the module to your home-manager config:

```nix
sharedModules = [ nix-ai.homeManagerModules.default ];
```

That's it. The module evaluates with **zero extra configuration** — every AI tool,
plugin, and permission rule comes preconfigured. (Local MLX inference stays idle
until you point it at a model; see [Usage](#usage).)

## How it works

nix-ai exports [home-manager](https://github.com/nix-community/home-manager) modules
that merge into your existing configuration:

| Export | What it includes |
| ------ | --------------- |
| `homeManagerModules.default` | The full AI stack — every tool below |
| `homeManagerModules.claude` | Just Claude Code |
| `homeManagerModules.codex` | Just OpenAI Codex |
| `homeManagerModules.mcp` | Just the MCP server catalog |
| `homeManagerModules.maestro` | Just Maestro orchestration |
| *(also: `agent-skills`, `antigravity-cli`, `antigravity-ide`, `cecli`, `qwen-code`)* | One module per tool |
| `lib.ci.claudeSettingsJson` | Pure settings JSON for CI validation (no derivations) |
| `lib.aiStackModels` | Role-name → model-ID registry, for foreign (non-module) consumers |

### Self-contained design

The module injects its own dependencies via `_module.args`. Your consuming flake
only needs two `follows` lines:

```nix
inputs.nixpkgs.follows = "nixpkgs";
inputs.home-manager.follows = "home-manager";
```

No AI-specific inputs to wire up, no extra configuration. It just works.

## Usage

Everything is enabled with sensible defaults. Common toggles on the default module:

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `programs.claude.model` | str or null | `null` | Override the default model (e.g. `"opus"`, `"sonnet"`) |
| `programs.claude.effortLevel` | enum or null | `null` | Reasoning effort (`"low"` / `"medium"` / `"high"`); null = upstream default |
| `programs.claude.settings.sandbox.enabled` | bool | `false` | Filesystem/network sandbox isolation |
| `programs.claude.trustedProjectDirs` | list of str | `[]` | Directories auto-trusted for CLAUDE.md imports |
| `services.aiStack.defaultLocalModelId` | str | `""` | Local MLX model ID; set to enable on-device inference |

Claude's full option schema comes from [nix-claude-code](https://github.com/dryvist/nix-claude-code);
the MCP catalog is documented in [`modules/mcp/README.md`](modules/mcp/README.md).

## Testing and validation

```bash
nix flake check   # nixfmt, statix, deadnix, shellcheck, and full module evaluation
nix fmt           # auto-fix formatting
bun test          # JavaScript test suite (bun:test is built-in — no install needed)
```

## Repository structure

```text
modules/
├── claude/         # Claude Code — plugins, hooks, agents, rules
├── codex/          # OpenAI Codex
├── antigravity-*/  # Gemini / Antigravity CLI + IDE
├── cecli/          # Cecli (Aider fork)
├── qwen-code/      # Alibaba Qwen Code
├── mcp/            # MCP server catalog, fanned out to every agent
├── mlx/            # MLX local inference (vllm-mlx, macOS)
├── fabric/         # Fabric prompt patterns + CLI
├── agent-skills/   # Cross-tool skill deployment
└── common/         # Shared permission engine and formatters
lib/                # Pure helpers (settings/registry generators, CI exports)
docs/               # Architecture notes (docs/architecture) and ADRs (docs/adr)
```

## License

[MIT](LICENSE)
