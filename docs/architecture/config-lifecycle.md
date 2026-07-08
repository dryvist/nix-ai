# Config Lifecycle: Build → Activation → Runtime

Nix home-manager generates configuration in three distinct phases. Understanding
which phase manages which file explains why changes sometimes need a full rebuild,
sometimes just a CLI command, and sometimes take effect immediately.

## Documents in This Directory

_This document is part of [`docs/architecture/`](README.md)._

## The Three Phases

```mermaid
graph LR
    P1["Phase 1\nBuild Time\n(Nix evaluation)"]
    P2["Phase 2\nActivation Time\n(darwin-rebuild switch)"]
    P3["Phase 3\nRuntime\n(between rebuilds)"]

    P1 -->|"writes to /nix/store/ (immutable)"| P2
    P2 -->|"merges into ~/.config/, ~/ (mutable)"| P3
    P3 -->|"CLI tools refresh specific files"| P3
```

### Phase 1: Build Time (Nix Evaluation)

Pure functional — no I/O, no network access, no filesystem queries. All inputs
must be declared in `options.nix`; the evaluator cannot call out to live services.

Outputs are immutable derivations in `/nix/store/`. They are referenced by Phase 2
activation scripts via Nix store paths baked into the derivation at evaluation time.

**Examples:**

- `modules/mlx/default.nix` → `pkgs.writeText "llama-swap-config.json"` (process management config)
- `modules/claude-config.nix` (+ `nix-claude-code` flake input) → JSON derivation for settings merge
- `modules/codex/settings.nix` → TOML derivation for config merge

**Constraint**: llama-swap runs directly against the immutable Nix store config —
its model list is exactly the Nix-declared registry (`services.aiStack` roles +
`programs.mlx.models`), and a registry change is a rebuild. Every other locally
cached model is served on demand by the dynamic tier (`programs.mlx.dynamicTier`,
an `mlx_lm.server` with no model argument that natively serves the whole HF
cache) — no runtime config mutation exists.

### Phase 2: Activation Time (darwin-rebuild switch)

`home.activation` scripts run during `home-manager activate` with full system access.
The separate `mlx-warmup` LaunchAgent runs after the proxy is ready and faults the
resident preload list into memory with 1-token requests.

The dominant pattern is **deep-merge**: the activation script overlays Nix-managed keys
onto the existing mutable file, preserving any keys Nix does not manage (auth tokens,
user preferences set via CLI, runtime state written by the tool itself).

See [`docs/adr/0002-activation-merge-pattern.md`](../adr/0002-activation-merge-pattern.md)
for why deep-merge is used instead of `home.file` symlinks.

### Phase 3: Runtime (Between Rebuilds)

CLI tools refresh specific config files without requiring a full `darwin-rebuild switch`.
These exist for configs that derive from live data that changes more frequently than
the Nix config itself (locally available MLX models).

## Activation Scripts Reference

All `home.activation` entries and their targets:

| Activation Name | Source File | Target File | What It Does |
|----------------|-------------|-------------|-------------|
| Claude settings merge | `nix-claude-code` flake input (wired via `modules/claude-config.nix`) | `~/.claude.json`, `~/.claude/settings.json` | MCP servers, project trust, permissions, plugins, hooks, model, sandbox |
| `knownMarketplacesMerge` | `nix-claude-code` flake input (`modules/settings.nix`) | `~/.claude/plugins/known_marketplaces.json` | Synthetic marketplace registry (installLocation + source) |
| `mergeAntigravitySettings` | `modules/antigravity-cli/settings.nix` | `~/.gemini/antigravity-cli/settings.json` | MCP servers, policies, folder trust |
| `codexConfigMerge` | `modules/codex/settings.nix` | `~/.codex/config.toml` | Model, MCP servers, approval policy |

## Config File Patterns

Not all config files use the same mechanism. The choice depends on whether the
consuming tool writes to its own config file at runtime.

| Pattern | Mechanism | Used When | Examples |
|---------|-----------|-----------|---------|
| **Nix store symlink** | `home.file` | Tool is read-only toward config | Plugin dirs, patterns, playbooks, copilot trusted folders |
| **Activation deep-merge** | `home.activation` + shell script | Tool writes runtime state to config | `~/.claude.json`, `~/.gemini/antigravity-cli/settings.json`, `~/.codex/config.toml` |
| **Store path direct** | LaunchAgent arg | Tool never writes its config | llama-swap (`--config <store path>`) |

### Why `home.file` Symlinks Break for Claude/Antigravity/Codex

Claude Code, Antigravity, and Codex all write to their config files at runtime:
authentication tokens, session state, user preferences set via `claude config set`, etc.

A `home.file` symlink points into `/nix/store/` which is world-readable but **not
writable** (mode `r-xr-xr-x`). Any runtime write from the tool would fail with
`Permission denied`, breaking login, settings persistence, and session state.

The deep-merge activation script creates (or updates) a real file at the target path,
owned by the user, writable at runtime. Nix-managed keys are overlaid each rebuild;
everything else is preserved.

## Runtime CLI Tools

These tools refresh specific files between rebuilds:

| Command | Refreshes | Trigger |
|---------|-----------|---------|
| `mlx-warmup` | resident model pages | After startup or when manually faulting the preload list |
| `mlx-switch <model>` | active registry model | Hot-swap active MLX model without restart |

Newly downloaded models need no refresh step at all: the dynamic tier
(`mlx_lm.server`) reads the HF cache per request, so a completed download is
immediately listed and servable.

## Diagram: Full File Ownership Map

```mermaid
graph TD
    subgraph BuildTime["Build Time — /nix/store/ (immutable)"]
        NS1["llama-swap-config.json derivation"]
        NS2["claude settings JSON derivation"]
        NS3["plugin/skill/rule Nix store paths"]
    end

    subgraph Activation["Activation Time — darwin-rebuild switch"]
        A2["claudeJsonMerge\n→ ~/.claude.json"]
        A3["claudeSettingsMerge\n→ ~/.claude/settings.json"]
    end

    subgraph Runtime["Runtime — mutable user files"]
        R1["llama-swap\n(reads NS1 store path directly)"]
        R2["~/.claude.json\n(Claude Code writes session state)"]
        R3["~/.claude/settings.json\n(Claude Code writes preferences)"]
    end

    subgraph Symlinks["home.file Symlinks — read-only"]
        S1["~/.claude/plugins/marketplaces/"]
        S2["~/.claude/commands/, agents/, skills/, rules/"]
        S3["~/.config/fabric/patterns/"]
        S4["~/Maestro/ playbooks"]
    end

    NS1 --> R1
    NS2 --> A2 --> R2
    NS2 --> A3 --> R3
    NS3 --> S1
    NS3 --> S2
    NS3 --> S3
    NS3 --> S4
```
