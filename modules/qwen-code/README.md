# Qwen Code

[Qwen Code](https://github.com/QwenLM/qwen-code) is Alibaba's terminal
coding agent — Claude-Code-style UX for Qwen3-Coder and any
OpenAI/Anthropic/Gemini-compatible endpoint. Apache-2.0.

## What it manages

- A soft activation check that the brew-installed `qwen` binary is on
  PATH (only fires on darwin). The actual brew install lives in
  nix-darwin's `homebrew.brews`, sourced from nix-ai's
  `lib.brewFormulae` flake output.
- A generated `~/.qwen/settings.json` wired to local llama-swap with
  one provider entry per capability-class alias from
  `services.aiStack.models`. Default startup model is the `coding`
  class.
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
- Doppler-wrapped `d-qwen` shell alias (declared in
  `modules/ai-aliases.zsh`) for sessions that need cloud-provider keys
  (Dashscope, OpenRouter, OpenAI, etc.).
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

## Routing

Routes to local MLX via llama-swap (`http://127.0.0.1:11434/v1`).

```nix
programs.qwen-code = {
  enable = true;
  model = "coding";  # capability-class alias
};
```

For cloud-provider sessions, use `d-qwen` (Doppler-injected from the ambient
`AI_DOPPLER_PROJECT`/`AI_DOPPLER_CONFIG`; see `modules/ai-aliases.zsh`).

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
