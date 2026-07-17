# cecli — Maintained Aider Fork

[`cecli`](https://github.com/cecli-dev/cecli) is an actively maintained
fork of [Aider](https://github.com/paul-gauthier/aider) (PyPI:
`cecli-dev`). Drop-in replacement — the same UX, the same `.aider`-style
yaml config, plus an `aider-ce` entry point for muscle memory.

This module replaced `programs.aider` after upstream Aider stopped
seeing maintenance. The previous module's option surface is preserved
under `programs.cecli` to ease migration.

## What it manages

- A real Nix derivation built from cecli-dev's PyPI sdist via
  `python3Packages.buildPythonApplication`. See
  [`modules/cecli/package.nix`](./package.nix) for the build
  definition; exposed as `pkgs.cecli` through this flake's
  `packages.<system>` output. Three entry points land on PATH:
  `cecli`, `aider-ce`, `ce.cli`.
- Three read-only generated config files — `~/.cecli.conf.yml`,
  `~/.cecli/cecli-meta.json`, `~/.cecli/cecli-settings.yml` — wired
  to the local MLX endpoint and the capability-class registry.
- Doppler-wrapped `d-cecli` shell alias (declared in
  `modules/ai-aliases.zsh`) for sessions that need cloud-provider
  keys.

## Why a local derivation (and not uvx / homebrew)

Per the repo install-order rule:

1. nixpkgs (if available)
2. Local Nix derivation (`buildPythonApplication`)
3. Homebrew (if it makes sense)

cecli isn't in nixpkgs and Homebrew has no formula, so we build from
PyPI as a real derivation in `package.nix`. This keeps everything
under Nix's deterministic graph — no `uv tool install` activation
hooks, no `~/.local/bin` shims, just a normal `home.packages` entry.

Two transitive deps require local packaging because nixpkgs-25.11
either doesn't ship them or ships an incompatible version: `py-cymbal`
(wheel; not in nixpkgs at all) and `mcp` 1.24.0 (sdist override —
nixpkgs ships 1.15 but cecli imports a symbol added in 1.24).
Earlier revisions of this file inlined five additional derivations
(four tree-sitter language wheels + `diff-match-patch`); nixpkgs-25.11
now ships all of those at compatible versions, so they came out.

uv2nix was evaluated as an alternative and rejected: it would shift
cecli's ~120-package closure from nixpkgs's curated supply chain to
raw PyPI metadata, exposing the build to fresh CVEs in upstream
releases. nixpkgs's slower bumps act as a security buffer for this
specific volatile dep graph. See `docs/architecture/per-agent-flakes.md`
for the full trade-off discussion.

Five version pins (`pypandoc>=1.15`, `litellm>=1.80.11`,
`watchfiles>=1.1.0`, `tomlkit>=0.14.0`, `xxhash>=3.6.0`) are relaxed
via `postPatch` against `requirements/requirements.in` — nixpkgs
ships slightly older versions, functionally compatible. The gap
closes the next time we bump nixpkgs.

## Routing

Routes to local MLX via llama-swap (`http://127.0.0.1:11434/v1`),
no API keys required.

```nix
programs.cecli = {
  enable = true;
  model = "openai/default"; # capability-class alias from services.aiStack.models
};
```

For cloud-provider sessions, use the Doppler-injected `d-cecli` shell
alias — it loads `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, etc. from the
ambient `AI_DOPPLER_PROJECT`/`AI_DOPPLER_CONFIG` (see `modules/ai-aliases.zsh`).

## Files written

| Path | Purpose |
| --- | --- |
| `~/.cecli.conf.yml` | Main config (read-only Nix-store symlink) |
| `~/.cecli/cecli-meta.json` | LiteLLM model metadata (context limits, costs) |
| `~/.cecli/cecli-settings.yml` | Per-model edit format + streaming overrides |

## Version pin

Pinned inside [`modules/cecli/package.nix`](./package.nix) with a
`# renovate: datasource=pypi depName=cecli-dev` annotation. Renovate
bumps the version + sha256; rebuilding picks up the new derivation.
The `cliVersions.cecli` entry in `vars/ai-stack.nix` documents the
intended version for non-Nix consumers but is no longer the source of
truth for the install.
