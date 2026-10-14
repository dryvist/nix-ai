# Qwen Code

[Qwen Code](https://github.com/QwenLM/qwen-code) is Alibaba's terminal
coding agent — Claude-Code-style UX for Qwen3-Coder and any
OpenAI/Anthropic/Gemini-compatible endpoint. Apache-2.0.

## What it manages

- A soft activation check that the brew-installed `qwen` binary is on
  PATH (only fires on darwin). The actual brew install lives in
  nix-darwin's `homebrew.brews`, sourced from nix-ai's
  capability-driven `lib.homebrewFor` flake output.
- A generated `~/.qwen/settings.json` wired to the host's selected endpoint.
  Hosts with a static Qwen resident use its physical catalog ID; other hosts
  keep their existing local role or router capability names.
- MCP servers rendered from the shared `programs.aiMcp.enabledServers`
  profile, with `programs.qwen-code.excludedMcpServers` reserved for
  Qwen-only compatibility gaps.
- `permissions` allow/ask/deny rules and `context.fileName`
  (`AGENTS.md`) generated from the shared permission engine, matching
  Codex and Antigravity. Only Bash command rules map across — Qwen's
  builtin tool names and prefix-less `WebFetch(host)` syntax differ, so
  Claude-specific extras are skipped.
- Shared skills linked from `~/.agents/skills` into `~/.qwen/skills`,
  matching Codex and Antigravity rather than maintaining a separate
  skill tree.
- On macOS, Qwen Code runs through a deny-default Seatbelt profile by
  default. It can read its Nix-managed settings and deployed skills, write
  only its session-state directories and the configured worktree, and reach
  the configured LiteLLM Local port plus the same outbound IP network as
  OpenCode. Other files in `~/.qwen` and other agents' config directories
  remain closed.
- On non-darwin hosts the module short-circuits silently — no
  install, no warning. Linux users need brew (or Linuxbrew) to use
  qwen-code through this module.

## Install matrix

| Order | Source | Implementation status |
| --- | --- | --- |
| 1 | nixpkgs | Not packaged upstream |
| 2 | Local Nix derivation (`buildNpmPackage`) | Deferred — qwen-code's npm workspace + cross-platform `optionalDependencies` (six per-OS `@lydell/node-pty` wheels + transitive ENOTCACHED gaps) need deeper packaging work than this PR's scope |
| 3 | Homebrew (`qwen-code`) | **Active** — formula lives in nix-darwin's `homebrew.brews` |

Per the repo's install-order rule. Brew works today — bottled,
~9k installs/30d, Apache-2.0, deps are `node` + `ripgrep` (both
already common). The `buildNpmPackage` path stays open as a future
follow-up when someone has the cycles to handle the workspace
optional-dep resolution properly.

## Model selection

When a host has a static resident for a Qwen catalog entry,
`programs.qwen-code.model` selects an MLX catalog key from
`programs.qwen-code.models`. Each allowed entry must be a Qwen model selected
as a static resident on the host. Qwen Code uses the catalog key as its
default and the provider points directly to that resident's loopback service
port. The default catalog key is `qwen38-27b` when that resident is available.

```nix
programs.qwen-code = {
  enable = true;
  model = "qwen38-27b";
  models = [ "qwen38-27b" ];
};
```

Hosts can extend `models` with catalog keys for additional Qwen models that
they serve as static residents. The selected model must be in that list.

Without a static Qwen resident, Qwen Code keeps the existing endpoint and
model behavior: `medium` for the local proxy or router, and `coding` for the
direct local endpoint. The router or proxy lists the capability aliases from
`modules/litellm-local/aliases.nix`; direct local serving lists the configured
roles. The model option's catalog-key assertion applies when a Qwen catalog
key is explicitly selected without a matching resident.

With the sandbox enabled, only `OPENAI_API_KEY` and `OPENAI_BASE_URL` are
forwarded from the launching shell. Other provider keys require explicitly
disabling `programs.qwen-code.sandbox.enable`. The sandbox requires a Nix
package so the launcher can name its executable; `installVia = "brew"` needs
the sandbox disabled.

## Adding cloud providers

`programs.qwen-code.extraSettings` is deep-merged into
`~/.qwen/settings.json`. Example:

```nix
programs.qwen-code.extraSettings = {
  modelProviders = [
    {
      name = "dashscope";
      protocol = "openai";
      baseUrl = "https://dashscope.aliyuncs.com/compatible-mode/v1";
      envKey = "DASHSCOPE_API_KEY";
      models = [ { name = "qwen3.6-coder-plus"; } ];
    }
  ];
};
```

The base `mlx-local-llama-swap` provider is preserved; new providers
are appended.

## Version pin

Pinned in `vars/ai-stack.nix` under `cliVersions.qwen-code`. Renovate
bumps the pin via the `# renovate: datasource=github-releases
depName=QwenLM/qwen-code` comment hint. The brew install resolves to
its own bottle version on each `brew update`; the pin in
`cliVersions` is documentation of the expected version.
