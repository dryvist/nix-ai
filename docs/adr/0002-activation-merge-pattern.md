# ADR 0002: Activation-Time Deep-Merge Instead of Nix Store Symlinks

**Status**: Accepted
**Date**: 2026-04-18

## Documents in This Directory

_This ADR is part of [`docs/adr/`](README.md)._

## Context

Nix home-manager has two primary mechanisms for managing files in the home directory:

1. **`home.file` symlink** — creates a symlink from `~/path/to/file` into `/nix/store/`.
   The file is immutable (mode `r-xr-xr-x`, owned by root). Any write to it fails with
   `Permission denied`.

2. **`home.activation` deep-merge** — runs a shell script during `home-manager activate`
   that overlays Nix-managed keys onto the existing mutable file, using `jq` or
   `merge-toml-settings.sh`. The file remains user-owned and writable at runtime.

The symlink approach is simpler and idempotent. The question is: when should the merge
approach be used instead?

## Decision

Use **activation-time deep-merge** for config files that the AI tools write to at runtime.
Use **`home.file` symlinks** for config files that are read-only from the tool's perspective.

**Files that require deep-merge** (tools write runtime state to these):

| File | Runtime writes |
|------|---------------|
| `~/.claude.json` | Session trust, auth tokens, `allowedTools` for project sessions |
| `~/.claude/settings.json` | User preferences set via `claude config set`, cached settings |
| `~/.claude/plugins/known_marketplaces.json` | Plugin cache state, indexed marketplace entries |
| `~/.gemini/settings.json` | Auth tokens, session preferences |
| `~/.codex/config.toml` | Auth state from `codex login` |

**Files that use `home.file` symlinks** (tools only read these):

- `~/.claude/plugins/marketplaces/<name>/` — plugin definitions (read-only)
- `~/.claude/commands/`, `~/.claude/skills/`, `~/.claude/rules/` — slash commands, skills, rules
- `~/.config/fabric/patterns/` — Fabric prompt patterns
- `~/Maestro/Auto Run Docs/` — Maestro playbooks
- `~/.copilot/config.json` — Copilot trusted folders (Copilot never writes here)
- `~/.gemini/policies/nix-managed.toml` — permission rules (Gemini reads, never writes)

## Consequences

**Positive:**

- AI tools can write runtime state (auth tokens, session settings) without breaking
- Nix-managed keys are restored on every `darwin-rebuild switch`, preventing drift
- Runtime-only keys (e.g., `allowedTools` set interactively) are preserved across rebuilds

**Negative:**

- Nix does not fully own the merged files — manual edits to Nix-managed keys survive
  until the next rebuild (potentially confusing)
- Merge scripts add complexity vs a single `home.file` declaration
- Ordering matters: activation scripts run after `writeBoundary`, so Nix store symlinks
  for other files are already in place when merge scripts run

**Practical implication**: If a Nix config change does not take effect after editing a
`.nix` file, check whether the target file uses deep-merge (requires `darwin-rebuild switch`)
or a symlink (updated immediately when the Nix store path changes).
