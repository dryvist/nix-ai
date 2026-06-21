# Per-Agent Module / Flake Pattern

## Why this exists

nix-ai grew organically: Claude, Antigravity, Codex, fabric, and (formerly)
Aider all live as sibling modules under `modules/`. Each has its own
shape, its own opinions about install source, its own depth of
configuration. Adding a new agent means re-deciding all of that.

The aider→cecli migration plus the addition of qwen-code (2026-05-04)
established a uniform layout that future agents — and existing ones,
when they're touched — should follow. The end-state goal is a clean
extraction: each agent module becomes its own small flake exposing a
home-manager module, so users can opt in/out per agent without pulling
the entire nix-ai surface area.

## Module layout

```text
modules/<agent>/
├── default.nix     ← module entry: imports + cfg.enable wiring
├── options.nix     ← user-facing options (model, routing, edit format, etc.)
├── package.nix     ← Nix derivation for the agent (nixpkgs path)
├── packages.nix    ← install-source wiring (home.packages = [pkgs.<agent>])
├── settings.nix    ← config-file generation (consumes vars/ai-stack.nix)
├── scripts/        ← (optional) READ-ONLY helpers (status checks etc.) —
│                     never install scripts; deps come from package.nix
└── README.md       ← what the agent does, install matrix, opt-in knobs
```

Reference implementations:

- `modules/cecli/` — Python derivation built from PyPI sdist via
  `python3Packages.buildPythonApplication`. Two inline derivations
  cover the transitive deps still missing from nixpkgs-25.11:
  `py-cymbal` (wheel, not in nixpkgs at all) and `mcp` 1.24.0 (sdist
  override of nixpkgs's older 1.15 — cecli imports a symbol added in
  1.24). Five version pins relaxed via `postPatch` against
  `requirements/requirements.in` (the gap closes when nixpkgs
  refreshes).
- `modules/qwen-code/` — brew-only install on darwin. The formula is
  declared by nix-darwin's `homebrew.brews`, sourced from this
  flake's `lib.brewFormulae` output. A `buildNpmPackage` derivation
  was attempted; qwen-code's workspace + cross-platform
  `optionalDependencies` need deeper packaging work and that path is
  deferred.

Existing modules (`modules/claude/`, `modules/antigravity-cli/`, `modules/codex/`,
`modules/fabric/`) predate this pattern. They work fine and are not
being refactored in the same PR — that's a follow-up sweep tracked
separately.

## Install-order rule

Per the repo's `nix-package-placement` rule:

1. **nixpkgs** if available (deterministic, GC-safe, cached binary)
2. **Local Nix derivation** (`modules/<agent>/package.nix`) when
   nixpkgs lacks the package — `buildPythonApplication`,
   `buildNpmPackage`, `buildGoModule`, etc. Override missing
   transitive deps inline as `let`-bound mini-derivations.
3. **Homebrew** if available, declared via nix-darwin's
   `homebrew.brews` (only when (1) and (2) are infeasible — e.g.
   GUI app, vendor-only distribution, or upstream packaging
   complexity beyond reasonable scope).

**Install scripts in home-manager activation are not on this list.**
They were the wrong answer for both cecli and qwen-code in an earlier
iteration of these modules; the correct answer is always one of the
three above, even when packaging requires extra work.

Each `packages.nix` exposes a `programs.<agent>.installVia` enum
option whose `default` reflects the preferred source for that agent
today. The enum is intentionally small — only sources that are
actually implemented — to surface bugs at eval time.

## Settings consumption — the central registry

All agents read from the same source of truth: `vars/ai-stack.nix`.
That file holds `models` (capability-class registry), `endpoints`,
`nodeports`, and `cliVersions`. nix-side consumers `import` it; non-nix
consumers read `~/.config/ai-stack/registry.json` (written every
rebuild from the same data).

A new agent must NOT hardcode model IDs, endpoint URLs, or version
strings. Reach into the registry instead.

## Brew-installed agents

Brew lives in nix-darwin (`homebrew.brews`), not home-manager. The
contract:

1. Agent's `packages.nix` adds the formula name to a list visible from
   the flake.
2. nix-ai's `flake.nix` aggregates those into the `lib.brewFormulae`
   output.
3. nix-darwin's host config consumes `inputs.nix-ai.lib.brewFormulae`
   and merges into `homebrew.brews`.
4. Agent's module includes a soft activation-time check that the
   binary is on PATH (warns rather than aborts, so users get a clear
   pointer when they enable the home-manager module without the
   companion nix-darwin rebuild).

`qwen-code` is the reference for this pattern.

## Locally-derived agents (Python from PyPI)

When nixpkgs lacks the agent and brew isn't on the table (Linux, or
the agent isn't bottled), package it from upstream as a real Nix
derivation in `modules/<agent>/package.nix`. Use
`python3Packages.buildPythonApplication` for Python tools,
`buildNpmPackage` for Node, `buildGoModule` for Go.

`cecli` is the reference for this pattern (Python). The shape:

1. `fetchPypi { pname = "<pkg>"; version = ...; hash = ...; }`
2. Explicit `build-system` and `dependencies` lists from upstream's
   `requirements.in` / `pyproject.toml`.
3. `# renovate: datasource=pypi depName=<pkg>` annotation on the
   version pin so Renovate manages bumps automatically.
4. Inline `let`-bound mini-derivations for transitive deps that
   nixpkgs lacks or ships at incompatible versions. cecli currently
   overrides two packages in this pattern: `py-cymbal` (wheel; not
   in nixpkgs at all) and `mcp` 1.24.0 (sdist override of nixpkgs's
   older 1.15 — cecli imports a symbol that 1.15 doesn't have).
5. `postPatch` to relax `>=` lower bounds on deps that nixpkgs ships
   at slightly older versions (functionally compatible, the bounds
   reflect upstream's "latest known good" tracking, not hard
   breakage).

### Risks worth tracking

| Risk | Mitigation |
| --- | --- |
| Transitive dep missing from nixpkgs | Add as inline `let`-bound mini-derivation in `package.nix` |
| Upstream version bound is tighter than nixpkgs | `substituteInPlace` to relax bound; verify cecli still works |
| Wheel uses platform-specific binaries | Conditional `fetchurl` on `stdenv.isDarwin` for wheel src |
| Sandbox-hostile transitive (test SIGKILL on darwin) | Skip via `skipDarwinChecks` in nix-home overlay |
| Native code missing symbols | Prefer `cp310-abi3` wheel over sdist when upstream offers both |

### Why not uv2nix

`uv2nix` (consume an upstream `uv.lock` directly, build the entire
closure from PyPI) is the natural alternative to manually mirroring
upstream's dep list. It was prototyped on cecli in PR #719 and
rejected for this specific module. The trade-off:

| Aspect | nixpkgs (this module) | uv2nix |
| --- | --- | --- |
| Dep source | `python3Packages` (curated, audit-backed) | PyPI (raw upstream resolution) |
| OSV scan exposure | Invisible to OSV (scanner doesn't read Nix) | Full surface (scanner walks `uv.lock`) |
| Version freshness | nixpkgs lag (~6 months) | Current PyPI |
| Verbose dep list | Yes (~30 names mirrored) | No (auto-derived from lockfile) |
| Lockfile to maintain | None | `uv.lock` (~2500 lines) |
| Flake input cost | 0 | 3 (`uv2nix`, `pyproject-nix`, `pyproject-build-systems`) |

For cecli's specific dep graph (~120 packages, fast-moving, multiple
deps with recent CVEs in the upstream version range), the security
trade-off dominates: nixpkgs's curation is a buffer that prevented
two CVE-affected packages (`litellm`, `diskcache`) from breaking the
build. uv2nix exposed both via `uv.lock` and the OSV gate failed.

`uv2nix` remains a viable choice for a *future* Python tool with a
small/stable dep graph where the verbose-dep-list cost outweighs the
nixpkgs-curation benefit. cecli isn't that case today.

## Path to standalone flakes

Each per-agent module is structured so it can graduate to its own flake
with no behavior change. The graduation recipe:

1. `git mv modules/<agent>/ ../nix-ai-<agent>/` into a new repo.
2. Add a minimal `flake.nix` that exports `homeManagerModules.default`
   from `default.nix`.
3. Declare `inputs.nix-ai.url = "github:dryvist/nix-ai"` so the
   extracted flake still consumes `vars/ai-stack.nix` as the central
   registry.
4. In nix-ai's `flake.nix`, replace the in-tree import with the new
   flake input.

The central registry stays in nix-ai. Individual agents extract; the
config layer doesn't fragment.

### When to extract

Extract when one of:

- The agent has its own release cadence that doesn't align with
  nix-ai's (e.g., Claude Code's near-daily updates).
- The module grew its own non-trivial dependencies that pollute
  nix-ai's flake lock.
- A user wants to opt out of the rest of nix-ai but still use this
  one agent.

Don't extract preemptively. cecli and qwen-code stay in-tree until
one of these triggers fires.

## Migration checklist for existing modules

When refactoring `modules/claude/`, `modules/antigravity-cli/`, `modules/codex/`,
or `modules/fabric/` to this pattern:

- [ ] Split `default.nix` into the 4-5 standard sub-files.
- [ ] Add `programs.<agent>.installVia` option, even if only one value
      is implemented today.
- [ ] Remove any hardcoded model IDs / endpoint URLs / version strings
      that should be in `vars/ai-stack.nix` (or already are).
- [ ] If the agent's preferred install source is brew, surface it via
      `lib.brewFormulae`.
- [ ] If the agent isn't in nixpkgs and brew isn't suitable, package
      it as a real Nix derivation in `modules/<agent>/package.nix`
      (see cecli for the Python pattern). NEVER add an
      `home.activation` hook that calls `pip install`, `npm install`,
      `uv tool install`, or similar.
- [ ] Write a README mirroring the cecli + qwen-code shape (What it
      manages, Install matrix, Routing, Version pin).
- [ ] Verify with `nix flake check` and a real `darwin-rebuild switch`.
