# cecli — Maintained Aider Fork

[`cecli`](https://github.com/cecli-dev/cecli) is an actively maintained
fork of [Aider](https://github.com/paul-gauthier/aider) (PyPI:
`cecli-dev`). Drop-in replacement — the same UX, the same `.aider`-style
yaml config, plus an `aider-ce` entry point for muscle memory.

This module replaced `programs.aider` after upstream Aider stopped
seeing maintenance. The previous module's option surface is preserved
under `programs.cecli` to ease migration.

## What it manages

- A uv2nix-built Python venv derivation. The
  [`pyproject.toml`](./pyproject.toml) shim declares cecli-dev as a
  pinned dep; [`uv.lock`](./uv.lock) records the hash-pinned closure
  (~120 packages); [`package.nix`](./package.nix) loads them into a
  `pythonSet` and exposes the venv as `pkgs.cecli` through this
  flake's `packages.<system>` output. Three entry points land on
  PATH: `cecli`, `aider-ce`, `ce.cli`.
- Three read-only generated config files — `~/.cecli.conf.yml`,
  `~/.cecli/cecli-meta.json`, `~/.cecli/cecli-settings.yml` — wired
  to the local MLX endpoint and the capability-class registry.
- Doppler-wrapped `d-cecli` shell alias (declared in
  `modules/ai-aliases.zsh`) for sessions that need cloud-provider
  keys.

## Why uv2nix (and not nixpkgs / uvx / homebrew)

Per the repo install-order rule:

1. nixpkgs (if available)
2. Local Nix derivation (uv2nix from a vendored `uv.lock`)
3. Homebrew (if it makes sense)

cecli isn't in nixpkgs and Homebrew has no formula, so we build it
locally. cecli's runtime closure spans ~120 packages; nixpkgs ships
some at versions incompatible with cecli (e.g. `mcp` 1.15 vs cecli's
required `>=1.24`) and doesn't ship others at all (`py-cymbal`).
Rather than carry inline overrides for each gap and a `postPatch`
ladder of relaxed lower bounds, we let uv resolve the closure from
PyPI directly and uv2nix turn that resolution into a Nix derivation.
The whole thing fits in ~50 lines of `package.nix`.

uv.lock is hash-pinned and Renovate-managed: bumping the version pin
in `pyproject.toml` triggers `uv lock --upgrade-package cecli-dev`
which regenerates the lockfile.

uv2nix is the repo standard for any new PyPI-fetched Python tool —
see [`docs/architecture/per-agent-flakes.md`](../../docs/architecture/per-agent-flakes.md).

## Routing

Defaults to local MLX via llama-swap (`http://127.0.0.1:11434/v1`),
no API keys required.

```nix
programs.cecli = {
  enable = true;
  routing = "llama-swap";   # default; alternative: "bifrost"
  model = "openai/default"; # capability-class alias from services.aiStack.models
};
```

For cloud-provider sessions, use the Doppler-injected `d-cecli` shell
alias — it loads `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, etc. from
`ai-ci-automation/prd`.

## Files written

| Path | Purpose |
| --- | --- |
| `~/.cecli.conf.yml` | Main config (read-only Nix-store symlink) |
| `~/.cecli/cecli-meta.json` | LiteLLM model metadata (context limits, costs) |
| `~/.cecli/cecli-settings.yml` | Per-model edit format + streaming overrides |

## Version pin

Pinned inside [`modules/cecli/pyproject.toml`](./pyproject.toml) with
a `# renovate: datasource=pypi depName=cecli-dev` annotation. Renovate
bumps the version, then runs `uv lock --upgrade-package cecli-dev` to
regenerate [`uv.lock`](./uv.lock) with the new hash-pinned closure.
The `cliVersions.cecli` entry in `vars/ai-stack.nix` documents the
intended version for non-Nix consumers but is no longer the source of
truth for the install.
