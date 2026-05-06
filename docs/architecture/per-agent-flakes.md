# Per-Agent Module / Flake Pattern

## Why this exists

nix-ai grew organically: Claude, Gemini, Codex, fabric, and (formerly)
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

- `modules/cecli/` — uv2nix-built Python venv. The runtime closure
  (~120 packages) is hash-pinned in `modules/cecli/uv.lock`,
  generated from a thin shim `pyproject.toml` that pins `cecli-dev`.
  `package.nix` is ~50 lines: load workspace, apply overlay, return
  `pythonSet.mkVirtualEnv`. The repo standard for any new
  PyPI-fetched Python tool — see "Locally-derived agents (Python from
  PyPI)" below for the rationale.
- `modules/qwen-code/` — brew-only install on darwin. The formula is
  declared by nix-darwin's `homebrew.brews`, sourced from this
  flake's `lib.brewFormulae` output. A `buildNpmPackage` derivation
  was attempted; qwen-code's workspace + cross-platform
  `optionalDependencies` need deeper packaging work and that path is
  deferred.

Existing modules (`modules/claude/`, `modules/gemini/`, `modules/codex/`,
`modules/fabric/`) predate this pattern. They work fine and are not
being refactored in the same PR — that's a follow-up sweep tracked
separately.

## Install-order rule

Per the repo's `nix-package-placement` rule:

1. **nixpkgs** if available (deterministic, GC-safe, cached binary)
2. **Local Nix derivation** (`modules/<agent>/package.nix`) when
   nixpkgs lacks the package — `uv2nix` (preferred for Python),
   `buildNpmPackage`, `buildGoModule`, etc. The Python flow uses a
   vendored `pyproject.toml` shim + `uv.lock` to build the closure
   from PyPI directly; see the cecli reference below.
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

## Locally-derived agents (Python from PyPI) — uv2nix

When nixpkgs lacks the agent and brew isn't on the table (Linux, or
the agent isn't bottled), package the Python tool with `uv2nix`. The
flake already exposes `pyproject-nix`, `uv2nix`, and
`pyproject-build-systems` as inputs — pass them through `callPackage`
to the agent's `package.nix`.

`cecli` is the reference. Three files per agent:

1. `modules/<agent>/pyproject.toml` — a thin shim declaring the
   upstream package as a single dep. Keep `requires-python` matching
   the nixpkgs default `python3` (currently 3.13). Add the
   `# renovate: datasource=pypi depName=<pkg>` annotation on the
   pinned `<pkg>==<ver>` line so Renovate bumps it.
2. `modules/<agent>/uv.lock` — generated by `uv lock` against the
   shim. Hash-pinned closure of every transitive dep, with both
   darwin and linux wheel URLs. Renovate's `lockfile-update` post-hook
   regenerates this on version bumps.
3. `modules/<agent>/package.nix` — ~50 lines:

   ```nix
   { lib, callPackage, python3, pyproject-nix, uv2nix, pyproject-build-systems }:
   let
     workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
     overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
     pythonSet = (callPackage pyproject-nix.build.packages { python = python3; }).overrideScope
       (lib.composeManyExtensions [
         pyproject-build-systems.overlays.wheel
         overlay
       ]);
     venv = pythonSet.mkVirtualEnv "<agent>" workspace.deps.default;
   in
   venv.overrideAttrs (old: { meta = (old.meta or { }) // { ... }; })
   ```

   The `mkVirtualEnv` derivation gets `bin/<entry-point>` and the
   full closure on PYTHONPATH. Override `meta` to attach
   `description`, `homepage`, `license`, `mainProgram`, `platforms`.

### Why uv2nix instead of `python3Packages.buildPythonApplication`

- **No version-mismatch overrides.** `buildPythonApplication` sources
  deps from `python3Packages`. When nixpkgs ships an older version
  than upstream requires (cecli's `mcp >=1.24` vs nixpkgs's 1.15)
  or doesn't ship a dep at all (`py-cymbal`), you carry inline
  mini-derivations to bridge the gap. uv2nix builds every dep from
  PyPI metadata directly, so nixpkgs version churn is decoupled
  from the agent's deps.
- **Hash-pinned supply chain.** Every wheel/sdist in `uv.lock`
  carries an sha256.
- **No `postPatch` lower-bound relaxation.** Same root cause —
  with PyPI as the source, the lockfile-pinned versions already
  satisfy upstream's bounds.
- **Smaller files.** ~50-line `package.nix` vs the
  300+-line manual-mirror form that `buildPythonApplication`
  required for a dep graph this size.

### When uv2nix is the wrong tool

- The upstream is a Go / Node / Rust binary — use `buildGoModule` /
  `buildNpmPackage` / `buildRustPackage`. uv2nix is Python-only.
- The Python tool has only a handful of nixpkgs-clean deps and you
  want a single-derivation `buildPythonApplication`. The win from
  uv2nix's lockfile machinery is small when the closure is tiny;
  the verbosity of carrying a `pyproject.toml` + `uv.lock` may not
  pay for itself. `modules/mcp/pal-package.nix` (5 deps, all in
  nixpkgs) is the example — kept on `buildPythonApplication`
  deliberately.

## Path to standalone flakes

Each per-agent module is structured so it can graduate to its own flake
with no behavior change. The graduation recipe:

1. `git mv modules/<agent>/ ../nix-ai-<agent>/` into a new repo.
2. Add a minimal `flake.nix` that exports `homeManagerModules.default`
   from `default.nix`.
3. Declare `inputs.nix-ai.url = "github:JacobPEvans/nix-ai"` so the
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

When refactoring `modules/claude/`, `modules/gemini/`, `modules/codex/`,
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
      (uv2nix for Python — see cecli; `buildNpmPackage` /
      `buildGoModule` for other ecosystems). NEVER add a
      `home.activation` hook that calls `pip install`, `npm install`,
      `uv tool install`, or similar.
- [ ] Write a README mirroring the cecli + qwen-code shape (What it
      manages, Install matrix, Routing, Version pin).
- [ ] Verify with `nix flake check` and a real `darwin-rebuild switch`.
